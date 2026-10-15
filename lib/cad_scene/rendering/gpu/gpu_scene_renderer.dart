import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' show Vector4;

import '../../cad_primitivies/face.dart';
import '../../camera_config.dart';
import '../tessellation/tessellated_scene.dart';
import 'gpu_scene_mesh.dart';

class GpuSceneRenderer extends ChangeNotifier {
  GpuSceneRenderer._(this._library) {
    _bodyPipeline = _context.createRenderPipeline(
      _bodyShader,
      _library['CadBodyFragment']!,
    );
    _edgePipeline = _context.createRenderPipeline(
      _edgeShader,
      _library['CadEdgeFragment']!,
    );
    _uniform = _context.createDeviceBuffer(gpu.StorageMode.hostVisible, 64);
    if (!_context.doesSupportOffscreenMSAA ||
        _context.defaultDepthStencilFormat != gpu.PixelFormat.d32FloatS8UInt) {
      throw UnsupportedError(
        'CAD GPU requires 4x offscreen MSAA and float32 depth on Metal.',
      );
    }
  }

  static Future<GpuSceneRenderer> create() async {
    final library = await gpu.ShaderLibrary.fromAsset(
      'shaders/cad.shaderbundle',
    );
    if (library == null) {
      throw StateError('CAD GPU shader bundle is unavailable.');
    }
    return GpuSceneRenderer._(library);
  }

  final gpu.ShaderLibrary _library;
  gpu.GpuContext get _context => gpu.gpuContext;
  gpu.Shader get _bodyShader => _library['CadBodyVertex']!;
  gpu.Shader get _edgeShader => _library['CadEdgeVertex']!;
  gpu.RenderPipeline? _bodyPipeline, _edgePipeline;
  gpu.DeviceBuffer? _uniform, _vertices, _indices, _edges;
  gpu.Texture? _depth, _msaa;
  gpu.GpuImageSurface? _surface;
  TessellatedScene? _scene;
  GpuSceneMesh? _mesh;
  Set<Face> _selected = {};
  final _uniformValues = Float32List(16);
  final _eyeHigh = Float32List(3);
  bool _busy = false, _disposed = false, _needsRepaint = false;
  CameraConfig? _lastCamera;
  ui.Size? _lastSize;
  double? _lastDpr;
  Completer<void>? _completion;
  int geometryUploads = 0, submissions = 0, completions = 0, busyPaints = 0;
  int targetRecreations = 0, maximumBackingTextures = 0;
  int _admittedColorTextures = 0;
  int uploadedGeometryBytes = 0, submittedDrawsPerFrame = 0;
  int get geometryBytes => _mesh?.byteLength ?? 0;
  int get drawsPerSubmission =>
      (_mesh?.bodyIndices.isNotEmpty == true ? 1 : 0) +
      (_mesh?.edgeVertices.isNotEmpty == true ? 1 : 0);
  Object? failure;
  int resourceBudgetStops = 0;
  final completionMicroseconds = <int>[];
  final completedFrameIds = <int>[];
  final completionTimestamps = <int>[];
  Future<void> get completed => _completion?.future ?? Future<void>.value();
  bool get waitingForGpu => _busy;

  gpu.BufferView _view(gpu.DeviceBuffer buffer) => gpu.BufferView(
    buffer,
    offsetInBytes: 0,
    lengthInBytes: buffer.sizeInBytes,
  );
  gpu.DeviceBuffer _upload(TypedData data) =>
      _context.createDeviceBufferWithCopy(ByteData.sublistView(data));

  ui.Image? render(
    CameraConfig camera,
    ui.Size size,
    double dpr,
    TessellatedScene scene, {
    Set<Face> selected = const {},
  }) {
    if (_disposed) throw StateError('Disposed CAD GPU renderer.');
    if (failure != null) throw StateError('CAD GPU stopped: $failure');
    if (size.isEmpty) return null;
    if (_busy) {
      busyPaints++;
      _needsRepaint = true;
      return null;
    }
    if (_lastCamera == camera &&
        _lastSize == size &&
        _lastDpr == dpr &&
        identical(_scene, scene) &&
        setEquals(_selected, selected)) {
      return _surface?.currentImage;
    }
    // The SDK surface has no acquire-without-allocation API. Fail closed at a
    // small budget, rather than silently grow a color target per camera frame.
    if (_admittedColorTextures >= 8) {
      failure = 'Flutter GPU image surface reached the eight-texture budget';
      resourceBudgetStops++;
      _releaseResources();
      throw StateError('$failure');
    }
    final width = (size.width * dpr).ceil(),
        height = (size.height * dpr).ceil();
    if (_surface?.width != width || _surface?.height != height) {
      // Resize only after producer completion. Drop ownership of all old size
      // attachments; Flutter retains any submitted display-list image itself.
      _surface = _context.createImageSurface(width, height);
      _depth = _context.createTexture(
        gpu.StorageMode.deviceTransient,
        width,
        height,
        format: _context.defaultDepthStencilFormat,
        sampleCount: 4,
        enableShaderReadUsage: false,
      );
      _msaa = _context.createTexture(
        gpu.StorageMode.deviceTransient,
        width,
        height,
        format: _context.defaultColorFormat,
        sampleCount: 4,
        enableShaderReadUsage: false,
      );
      targetRecreations++;
    }
    if (!identical(_scene, scene)) {
      _mesh = GpuSceneMesh(scene)..select(selected);
      _scene = scene;
      _selected = Set.of(selected);
      _vertices = _mesh!.bodyVertices.isEmpty
          ? null
          : _upload(_mesh!.bodyVertices);
      _indices = _mesh!.bodyIndices.isEmpty
          ? null
          : _upload(_mesh!.bodyIndices);
      _edges = _mesh!.edgeVertices.isEmpty
          ? null
          : _upload(_mesh!.edgeVertices);
      uploadedGeometryBytes = geometryBytes;
      submittedDrawsPerFrame = drawsPerSubmission;
      geometryUploads++;
    } else if (!setEquals(_selected, selected)) {
      _mesh!.select(selected);
      _selected = Set.of(selected);
      if (_vertices != null &&
          !_vertices!.overwrite(ByteData.sublistView(_mesh!.bodyVertices))) {
        throw StateError('CAD selection upload failed');
      }
      _vertices?.flush();
    }
    final p = camera.position.vector;
    _eyeHigh.setAll(0, [p.x, p.y, p.z]);
    _uniformValues.setAll(0, [
      p.x,
      p.y,
      p.z,
      0,
      p.x - _eyeHigh[0],
      p.y - _eyeHigh[1],
      p.z - _eyeHigh[2],
      0,
      math.cos(-camera.yaw),
      math.sin(-camera.yaw),
      math.cos(-camera.pitch),
      math.sin(-camera.pitch),
      size.width,
      size.height,
      camera.focalLength,
      dpr,
    ]);
    if (!_uniform!.overwrite(ByteData.sublistView(_uniformValues))) {
      throw StateError('CAD camera upload failed');
    }
    _uniform!.flush();
    final command = _context.createCommandBuffer();
    final previousTextureCount = _surface!.debugBackingTextureCount;
    final frame = _surface!.acquireNextFrame();
    _admittedColorTextures +=
        _surface!.debugBackingTextureCount - previousTextureCount;
    maximumBackingTextures = math.max(
      maximumBackingTextures,
      _admittedColorTextures,
    );
    try {
      final pass = command.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: _msaa!,
            resolveTexture: frame.colorTexture,
            storeAction: gpu.StoreAction.multisampleResolve,
            clearValue: Vector4.zero(),
          ),
          depthStencilAttachment: gpu.DepthStencilAttachment(
            texture: _depth!,
            depthClearValue: 0,
          ),
        ),
      );
      pass.setCullMode(gpu.CullMode.none);
      pass.setDepthCompareOperation(gpu.CompareFunction.greaterEqual);
      pass.setColorBlendEnable(false);
      if (_indices != null) {
        pass.bindPipeline(_bodyPipeline!);
        pass.bindUniform(
          _bodyShader.getUniformSlot('Camera'),
          _view(_uniform!),
        );
        pass.bindVertexBuffer(_view(_vertices!));
        pass.bindIndexBuffer(_view(_indices!), gpu.IndexType.int32);
        pass.setDepthWriteEnable(true);
        pass.drawIndexed(_mesh!.bodyIndices.length);
      }
      if (_edges != null) {
        pass.clearBindings();
        pass.bindPipeline(_edgePipeline!);
        pass.bindUniform(
          _edgeShader.getUniformSlot('Camera'),
          _view(_uniform!),
        );
        pass.bindVertexBuffer(_view(_edges!));
        pass.setDepthWriteEnable(false);
        pass.draw(_mesh!.edgeVertices.length ~/ 15);
      }
      frame.present(command);
      _busy = true;
      final completion = _completion = Completer<void>();
      final start = developer.Timeline.now, id = ++submissions;
      command.submit(
        completionCallback: (success) {
          _busy = false;
          completions++;
          if (!success) {
            failure = 'GPU command $id failed';
            _releaseResources();
          }
          if (!_disposed && completionMicroseconds.length < 8192) {
            completionMicroseconds.add(developer.Timeline.now - start);
            completionTimestamps.add(developer.Timeline.now);
            completedFrameIds.add(id);
          }
          completion.complete();
          // Busy paints are counted separately; a completion can request a fresh
          // camera paint, but it must never be counted as a new camera submission.
          if (!_disposed && (_needsRepaint || !success)) {
            _needsRepaint = false;
            notifyListeners();
          }
        },
      );
      _lastCamera = camera;
      _lastSize = size;
      _lastDpr = dpr;
      return _surface!.currentImage;
    } catch (error) {
      frame.discard();
      _busy = false;
      final completion = _completion;
      if (completion != null && !completion.isCompleted) completion.complete();
      failure = error;
      _releaseResources();
      rethrow;
    }
  }

  void stop(Object reason) {
    failure = reason;
    _releaseResources();
  }

  @override
  void dispose() {
    _disposed = true;
    // This preview SDK exposes native finalizers, no explicit buffer/texture
    // destroy. Drop every owned reference; in-flight commands keep theirs alive.
    _releaseResources();
    completionMicroseconds.clear();
    completedFrameIds.clear();
    completionTimestamps.clear();
    super.dispose();
  }

  void _releaseResources() {
    _surface = null;
    _depth = null;
    _msaa = null;
    _vertices = null;
    _indices = null;
    _edges = null;
    _uniform = null;
    _bodyPipeline = null;
    _edgePipeline = null;
    _mesh = null;
    _scene = null;
    _lastCamera = null;
    _lastSize = null;
    _lastDpr = null;
    _selected.clear();
  }
}
