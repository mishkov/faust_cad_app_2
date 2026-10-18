import Cocoa
import FlutterMacOS
import MetalKit

private final class FrameSlot {
  var busy = false
  var generation = -1
  var selection: MTLBuffer?
  var clipped = [Int: MTLBuffer]()
}

final class MetalViewportRenderer: NSObject, MTKViewDelegate {
  let device: MTLDevice
  private let queue: MTLCommandQueue
  let sampleCount: Int
  private let fillPipeline: MTLRenderPipelineState, linePipeline: MTLRenderPipelineState,
    depthPipeline: MTLRenderPipelineState
  private let depthWrite: MTLDepthStencilState, depthRead: MTLDepthStencilState,
    noDepth: MTLDepthStencilState
  private let slots = [FrameSlot(), FrameSlot()]
  private weak var view: MTKView?
  private var body: MetalMesh?, sketches = [MetalMesh](), camera: MetalCamera?
  private var hoveredFace = -1
  private var hoverLines: MTLBuffer?
  private var hoverLineCount = 0
  private var selection = [Int](), wireframe = false, clear = MTLClearColorMake(1, 1, 1, 1)
  private var serial: Int64 = 0, lastSubmitted: Int64 = -1, lastPresented: Int64 = -1
  private var stopped = false, forceDraw = true, capturing = false
  private var receivedAt = CACurrentMediaTime(), targetGeneration = 0
  private var submitted = 0, presented = 0, coalesced = 0, preciseFrames = 0, peakInFlight = 0
  private var geometryGeneration = 0
  private var gpuMS = [Double](), latencyMS = [Double](), presentedAt = [Double]()
  var onError: ((String) -> Void)?
  private(set) var failure: String?

  init(configuration: Void) throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
      let shaderURL = Bundle.main.url(forResource: "CadShaders", withExtension: "metal")
    else { throw MetalFailure("Metal device, queue or shader source unavailable") }
    let library = try device.makeLibrary(
      source: String(contentsOf: shaderURL, encoding: .utf8), options: nil)
    self.device = device
    self.queue = queue
    let samples =
      device.supportsTextureSampleCount(8) ? 8 : (device.supportsTextureSampleCount(4) ? 4 : 1)
    sampleCount = samples
    func pipeline(_ vertex: String, _ fragment: String, colorWrites: Bool = true) throws
      -> MTLRenderPipelineState
    {
      let p = MTLRenderPipelineDescriptor()
      p.vertexFunction = library.makeFunction(name: vertex)
      p.fragmentFunction = library.makeFunction(name: fragment)
      p.rasterSampleCount = samples
      p.depthAttachmentPixelFormat = .depth32Float
      let c = p.colorAttachments[0]!
      c.writeMask = colorWrites ? .all : []
      c.pixelFormat = .bgra8Unorm
      c.isBlendingEnabled = true
      c.sourceRGBBlendFactor = .one
      c.destinationRGBBlendFactor = .oneMinusSourceAlpha
      c.sourceAlphaBlendFactor = .one
      c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
      return try device.makeRenderPipelineState(descriptor: p)
    }
    depthPipeline = try pipeline("cadBody", "cadFill", colorWrites: false)
    fillPipeline = try pipeline("cadBody", "cadFill")
    linePipeline = try pipeline("cadLine", "cadStroke")
    func depth(_ write: Bool, _ compare: MTLCompareFunction) -> MTLDepthStencilState {
      let d = MTLDepthStencilDescriptor()
      d.isDepthWriteEnabled = write
      d.depthCompareFunction = compare
      return device.makeDepthStencilState(descriptor: d)!
    }
    depthWrite = depth(true, .greaterEqual)
    depthRead = depth(false, .greaterEqual)
    noDepth = depth(false, .always)
    super.init()
  }

  func attach(_ view: MTKView) {
    self.view = view
    view.device = device
    view.delegate = self
    view.colorPixelFormat = .bgra8Unorm
    view.depthStencilPixelFormat = .depth32Float
    view.sampleCount = sampleCount
    view.clearDepth = 0
    view.framebufferOnly = true
    view.isPaused = true
    view.enableSetNeedsDisplay = true
    view.autoResizeDrawable = false
    if let layer = view.layer as? CAMetalLayer {
      layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
      layer.maximumDrawableCount = 3
      layer.allowsNextDrawableTimeout = true
    }
    requestDraw()
  }

  func update(_ packet: [String: Any]) throws {
    guard !stopped else { throw MetalFailure("Metal renderer is disposed") }
    let nextCamera = try MetalCamera(packet["camera"])
    // Validate and allocate the complete revision before replacing visible state.
    let nextBody = try (packet["mesh"] as? [String: Any]).map { try MetalMesh($0, device: device) }
    let nextSketches = try (packet["sketches"] as? [[String: Any]]).map {
      try $0.map { try MetalMesh($0, device: device) }
    }
    var nextHoverLines: MTLBuffer?
    var nextHoverCount: Int?
    if let data = packet["hoverLines"] {
      let values = try typedArray(data, Float.self)
      guard values.count % 90 == 0, values.allSatisfy({ $0.isFinite }) else {
        throw MetalFailure("Invalid hover boundary lines")
      }
      nextHoverCount = values.count / 15
      if !values.isEmpty {
        nextHoverLines = values.withUnsafeBytes {
          device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        }
        guard nextHoverLines != nil else { throw MetalFailure("Hover allocation failed") }
      }
    }
    var nextClear = clear
    if let colors = packet["clear"] {
      let c = try typedArray(colors, Double.self)
      guard c.count == 4, c.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else {
        throw MetalFailure("Invalid Metal clear color")
      }
      nextClear = MTLClearColorMake(c[0], c[1], c[2], c[3])
    }
    if camera != nil && serial > lastSubmitted { coalesced += 1 }
    if nextBody != nil || nextSketches != nil {
      geometryGeneration += 1
      for slot in slots where !slot.busy {
        slot.clipped.removeAll()
        slot.selection = nil
        slot.generation = geometryGeneration
      }
    }
    if let mesh = nextBody { body = mesh }
    if let meshes = nextSketches { sketches = meshes }
    if let count = nextHoverCount {
      hoverLines = nextHoverLines
      hoverLineCount = count
    }
    hoveredFace = (packet["hoveredFace"] as? NSNumber)?.intValue ?? -1
    camera = nextCamera
    selection = (packet["selection"] as? [NSNumber] ?? []).map { $0.intValue }
    wireframe = packet["wireframe"] as? Bool ?? false
    clear = nextClear
    serial = (packet["serial"] as? NSNumber)?.int64Value ?? serial + 1
    receivedAt = CACurrentMediaTime()
    requestDraw()
  }

  private func requestDraw() {
    guard !stopped, let view = view, let camera = camera else { return }
    let size = CGSize(
      width: ceil(camera.width * camera.dpr), height: ceil(camera.height * camera.dpr))
    if view.drawableSize != size {
      view.drawableSize = size
      targetGeneration += 1
      forceDraw = true
    }
    view.needsDisplay = true
  }
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { forceDraw = true }

  func draw(in view: MTKView) {
    guard !stopped, failure == nil, let camera = camera, forceDraw || serial != lastSubmitted,
      let slot = slots.first(where: { !$0.busy }),
      let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
      let command = queue.makeCommandBuffer()
    else { return }
    do {
      descriptor.colorAttachments[0].clearColor = clear
      descriptor.depthAttachment.clearDepth = 0
      try encode(command, descriptor: descriptor, camera: camera, slot: slot)
      slot.busy = true
      forceDraw = false
      lastSubmitted = serial
      submitted += 1
      peakInFlight = max(peakInFlight, slots.filter({ $0.busy }).count)
      let frame = serial
      let start = receivedAt
      drawable.addPresentedHandler { [weak self] drawable in
        let time = drawable.presentedTime
        DispatchQueue.main.async {
          guard let self = self, !self.stopped, frame > self.lastPresented, time > 0 else { return }
          self.lastPresented = frame
          self.presented += 1
          self.append(&self.presentedAt, time)
          self.append(&self.latencyMS, max(0, (time - start) * 1000))
        }
      }
      command.addCompletedHandler { [weak self, slot] command in
        DispatchQueue.main.async {
          slot.busy = false
          guard let self = self, !self.stopped else { return }
          if slot.generation != self.geometryGeneration {
            slot.clipped.removeAll()
            slot.selection = nil
            slot.generation = self.geometryGeneration
          }
          if command.status == .error {
            self.fail(command.error?.localizedDescription ?? "Metal command failed")
          }
          if command.gpuEndTime > command.gpuStartTime {
            self.append(&self.gpuMS, (command.gpuEndTime - command.gpuStartTime) * 1000)
          }
          if self.serial != self.lastSubmitted { self.requestDraw() }
        }
      }
      command.present(drawable)
      command.commit()
    } catch { fail(String(describing: error)) }
  }

  private func fail(_ message: String) {
    failure = message
    onError?(message)
  }
  func resetMetrics() -> Double {
    submitted = 0
    presented = 0
    coalesced = 0
    preciseFrames = 0
    peakInFlight = 0
    gpuMS = []
    latencyMS = []
    presentedAt = []
    return CACurrentMediaTime()
  }
  private func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    return status == KERN_SUCCESS ? info.resident_size : 0
  }
  private func append(_ values: inout [Double], _ value: Double) {
    if values.count >= 4096 { values.removeFirst(1024) }
    values.append(value)
  }

  private func encode(
    _ command: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, camera: MetalCamera,
    slot: FrameSlot
  ) throws {
    if slot.generation != geometryGeneration {
      slot.clipped.removeAll()
      slot.selection = nil
      slot.generation = geometryGeneration
    }
    guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else {
      throw MetalFailure("Metal render encoder unavailable")
    }
    defer { encoder.endEncoding() }
    encoder.setCullMode(.none)
    encoder.setViewport(
      MTLViewport(
        originX: 0, originY: 0, width: camera.width * camera.dpr,
        height: camera.height * camera.dpr, znear: 0, zfar: 1))
    let count = max(1, body?.faceCount ?? 0)
    let bytes = max(256, count * 4)
    if slot.selection == nil || slot.selection!.length < bytes {
      slot.selection = device.makeBuffer(length: bytes, options: .storageModeShared)
    }
    guard let selected = slot.selection else {
      throw MetalFailure("Metal selection allocation failed")
    }
    memset(selected.contents(), 0, selected.length)
    let ids = selected.contents().bindMemory(to: UInt32.self, capacity: count)
    for id in selection where id >= 0 && id < count { ids[id] = 1 }
    if hoveredFace >= 0 && hoveredFace < count { ids[hoveredFace] |= 2 }
    encoder.setVertexBuffer(selected, offset: 0, index: 2)
    let meshes = [body].compactMap({ $0 }) + sketches
    // Scale reverse Z to the conservative nearest scene bound when the whole
    // scene is in front. This uses the full depth range without discarding any
    // geometry; crossing views retain the physical 1e-6 clipping plane.
    let minimumDepth = meshes.map { $0.minimumDepth(camera) }.min() ?? .infinity
    let maximumDepth = meshes.map { $0.maximumDepth(camera) }.max() ?? 1
    let depthScale: Float = camera.orthographicDistance > 0
      ? Float(1 / max(1, maximumDepth * 1.01))
      : (minimumDepth.isFinite && minimumDepth > 0 ? Float(max(1e-6, minimumDepth * 0.5)) : 1e-6)
    slot.clipped = slot.clipped.filter { $0.key < meshes.count }
    var clippedThisFrame = false
    for (index, mesh) in meshes.enumerated() {
      guard mesh.visible(camera) else { continue }
      let precise = mesh.needsPreciseClip(camera)
      var uniforms = camera.uniforms(precise: precise, wireframe: wireframe, depthScale: depthScale)
      encoder.setVertexBytes(&uniforms, length: 80, index: 1)
      encoder.setDepthStencilState(mesh.plane == nil ? depthWrite : depthRead)
      encoder.setDepthBias(0, slopeScale: mesh.plane == nil ? 0 : 1, clamp: 0)
      if !wireframe || mesh.plane != nil || !sketches.isEmpty, mesh.indexCount > 0 {
        encoder.setRenderPipelineState(
          wireframe && mesh.plane == nil ? depthPipeline : fillPipeline)
        if precise {
          clippedThisFrame = true
          let vertices = mesh.clipped(camera)
          if !vertices.isEmpty {
            let length = vertices.count * 4
            if slot.clipped[index] == nil || slot.clipped[index]!.length < length {
              slot.clipped[index] = device.makeBuffer(length: length, options: .storageModeShared)
            }
            guard let buffer = slot.clipped[index] else {
              throw MetalFailure("Metal near-plane allocation failed")
            }
            vertices.withUnsafeBytes {
              buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: length)
            }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.drawPrimitives(
              type: .triangle, vertexStart: 0, vertexCount: vertices.count / 12)
          }
        } else if let v = mesh.vertices, let indices = mesh.indices {
          encoder.setVertexBuffer(v, offset: 0, index: 0)
          encoder.drawIndexedPrimitives(
            type: .triangle, indexCount: mesh.indexCount, indexType: .uint32, indexBuffer: indices,
            indexBufferOffset: 0)
        }
      }
      encoder.setDepthBias(0, slopeScale: 0, clamp: 0)
      if let lines = mesh.lines {
        uniforms = camera.uniforms(precise: false, wireframe: wireframe, depthScale: depthScale)
        encoder.setVertexBytes(&uniforms, length: 80, index: 1)
        encoder.setRenderPipelineState(linePipeline)
        encoder.setDepthStencilState(wireframe && mesh.plane == nil ? noDepth : depthRead)
        encoder.setVertexBuffer(lines, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.lineCount)
      }
    }
    if let lines = hoverLines, hoverLineCount > 0 {
      var uniforms = camera.uniforms(precise: false, wireframe: wireframe, depthScale: depthScale)
      encoder.setVertexBytes(&uniforms, length: 80, index: 1)
      encoder.setRenderPipelineState(linePipeline)
      encoder.setDepthStencilState(wireframe ? noDepth : depthRead)
      encoder.setVertexBuffer(lines, offset: 0, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: hoverLineCount)
    }
    if clippedThisFrame { preciseFrames += 1 }
  }

  func capture(_ result: @escaping FlutterResult) {
    guard !capturing, !stopped, let camera = camera else {
      result(
        FlutterError(
          code: "capture_busy", message: "No frame or capture already in progress", details: nil))
      return
    }
    capturing = true
    do {
      let w = Int(ceil(camera.width * camera.dpr))
      let h = Int(ceil(camera.height * camera.dpr))
      func texture(_ format: MTLPixelFormat, _ samples: Int, _ shared: Bool) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
          pixelFormat: format, width: w, height: h, mipmapped: false)
        d.sampleCount = samples
        d.textureType = samples > 1 ? .type2DMultisample : .type2D
        d.storageMode = shared ? .shared : .private
        d.usage = [.renderTarget]
        guard let t = device.makeTexture(descriptor: d) else {
          throw MetalFailure("Metal capture target allocation failed")
        }
        return t
      }
      let output = try texture(.bgra8Unorm, 1, true)
      let depth = try texture(.depth32Float, sampleCount, false)
      let d = MTLRenderPassDescriptor()
      let c = d.colorAttachments[0]!
      c.texture = sampleCount > 1 ? try texture(.bgra8Unorm, sampleCount, false) : output
      c.resolveTexture = sampleCount > 1 ? output : nil
      c.loadAction = .clear
      c.storeAction = sampleCount > 1 ? .multisampleResolve : .store
      c.clearColor = clear
      d.depthAttachment.texture = depth
      d.depthAttachment.loadAction = .clear
      d.depthAttachment.storeAction = .dontCare
      d.depthAttachment.clearDepth = 0
      guard let command = queue.makeCommandBuffer() else {
        throw MetalFailure("Metal capture command allocation failed")
      }
      let slot = FrameSlot()
      try encode(command, descriptor: d, camera: camera, slot: slot)
      command.addCompletedHandler { [weak self, slot] command in
        // Capture owns its targets and slot until completion, independently of live slots.
        _ = slot
        if command.status == .error {
          DispatchQueue.main.async {
            self?.capturing = false
            result(
              FlutterError(
                code: "metal_capture", message: command.error?.localizedDescription, details: nil))
          }
          return
        }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        output.getBytes(
          &bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        DispatchQueue.main.async {
          self?.capturing = false
          result(["width": w, "height": h, "bgra": FlutterStandardTypedData(bytes: Data(bytes))])
        }
      }
      command.commit()
    } catch {
      capturing = false
      result(FlutterError(code: "metal_capture", message: String(describing: error), details: nil))
    }
  }

  func stats() -> [String: Any] {
    let memory = ([body].compactMap({ $0 }) + sketches).reduce(0) { $0 + $1.bytes }
    return [
      "device": device.name, "samples": sampleCount, "submitted": submitted, "presented": presented,
      "lastPresented": lastPresented, "lastRequested": serial, "coalesced": coalesced,
      "inFlight": slots.filter({ $0.busy }).count,
      "peakInFlight": peakInFlight, "frameSlots": 2, "maximumDrawables": 3, "geometryBytes": memory,
      "transientBytes": (hoverLines?.length ?? 0) + slots.reduce(0) {
        $0 + ($1.selection?.length ?? 0) + $1.clipped.values.reduce(0) { $0 + $1.length }
      },
      "precisionClipFrames": preciseFrames, "targetGeneration": targetGeneration,
      "geometryUploads": geometryGeneration,
      "gpuMilliseconds": gpuMS,
      "requestToPresentMilliseconds": latencyMS, "presentedAtSeconds": presentedAt,
      "nativeTime": CACurrentMediaTime(),
      "residentBytes": residentBytes(), "metalAllocatedBytes": device.currentAllocatedSize,
      "error": failure as Any? ?? NSNull(),
    ]
  }
  func stop() {
    stopped = true
    view?.delegate = nil
    view?.isPaused = true
    view = nil
    body = nil
    sketches = []
    hoverLines = nil
    hoverLineCount = 0
    for slot in slots {
      slot.clipped = [:]
      slot.selection = nil
    }
  }
}
