import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../cad_primitivies/face.dart';
import '../../camera_config.dart';
import '../tessellation/tessellated_scene.dart';
import '../shaded_scene_renderer.dart';
import 'gpu_scene_renderer.dart';

class GpuViewport extends StatefulWidget {
  const GpuViewport({
    super.key,
    required this.camera,
    required this.scene,
    required this.selected,
  });
  final CameraConfig camera;
  final TessellatedScene scene;
  final Set<Face> selected;

  @override
  State<GpuViewport> createState() => _GpuViewportState();
}

class _GpuViewportState extends State<GpuViewport> {
  GpuSceneRenderer? _renderer;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
        throw UnsupportedError(
          'The CAD GPU prototype currently targets macOS Impeller.',
        );
      }
      final renderer = await GpuSceneRenderer.create();
      if (!mounted) {
        renderer.dispose();
        return;
      }
      setState(() => _renderer = renderer);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('CAD GPU unavailable: $_error'));
    }
    final renderer = _renderer;
    if (renderer == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return CustomPaint(
      painter: _GpuViewportPainter(
        renderer,
        widget.camera,
        widget.scene,
        widget.selected,
        MediaQuery.devicePixelRatioOf(context),
      ),
    );
  }

  @override
  void dispose() {
    _renderer?.dispose();
    super.dispose();
  }
}

// A private painter belongs with its owning widget; it owns no native resources.
class _GpuViewportPainter extends CustomPainter {
  _GpuViewportPainter(
    this.renderer,
    this.camera,
    this.scene,
    this.selected,
    this.dpr,
  ) : super(repaint: renderer);
  final GpuSceneRenderer renderer;
  final CameraConfig camera;
  final TessellatedScene scene;
  final Set<Face> selected;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    if (renderer.failure != null) {
      final text = TextPainter(
        text: TextSpan(
          text:
              'Experimental GPU backend stopped: ${renderer.failure}.\nUse CAD_RENDER_BACKEND=canvas for the reference viewport.',
          style: const TextStyle(color: Colors.black, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      text.paint(canvas, const Offset(12, 12));
      text.dispose();
      return;
    }
    ui.Image? image;
    try {
      image = renderer.render(camera, size, dpr, scene, selected: selected);
    } catch (error) {
      renderer.stop(error);
      paint(canvas, size);
      return;
    }
    if (image == null) {
      if (renderer.waitingForGpu) {
        ShadedSceneRenderer(
          camera,
          devicePixelRatio: dpr,
        ).paint(canvas, size, scene, selectedFaces: selected);
      }
      return;
    }
    try {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.none,
      );
    } finally {
      image.dispose();
    }
  }

  @override
  bool shouldRepaint(_GpuViewportPainter oldDelegate) => true;
}
