import Cocoa
import FlutterMacOS
import MetalKit

final class CadMetalPlugin: NSObject, FlutterPlugin {
  private var renderers = [Int64: MetalViewportRenderer]()
  private var nextID: Int64 = 1
  private var channel: FlutterMethodChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = CadMetalPlugin()
    let channel = FlutterMethodChannel(name: "cad.metal", binaryMessenger: registrar.messenger)
    plugin.channel = channel
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.register(CadMetalViewFactory(plugin), withId: "cad.metal.viewport")
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      let packet = call.arguments as? [String: Any] ?? [:]
      if call.method == "create" {
        let id = nextID
        nextID += 1
        let renderer = try MetalViewportRenderer(configuration: ())
        renderer.onError = { [weak self] message in
          self?.channel?.invokeMethod("error", arguments: ["id": id, "message": message])
        }
        renderers[id] = renderer
        result(id)
        return
      }
      if call.method == "environment" {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        result([
          "activeRenderers": renderers.count, "pid": ProcessInfo.processInfo.processIdentifier,
          "foregroundPid": front,
          "desktopUnlocked": (session["kCGSSessionOnConsoleKey"] as? Bool ?? false)
            && !(session["CGSSessionScreenIsLocked"] as? Bool ?? false),
        ])
        return
      }
      guard let number = packet["id"] as? NSNumber else {
        throw MetalFailure("Missing renderer ID")
      }
      let id = number.int64Value
      if call.method == "dispose" {
        remove(id)
        result(nil)
        return
      }
      guard let renderer = renderers[id] else { throw MetalFailure("Unknown Metal renderer") }
      switch call.method {
      case "update":
        try renderer.update(packet)
        result(nil)
      case "stats": result(renderer.stats())
      case "resetMetrics":
        result(renderer.resetMetrics())
      case "capture": renderer.capture(result)
      default: result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "metal", message: String(describing: error), details: nil))
    }
  }

  func remove(_ id: Int64) { renderers.removeValue(forKey: id)?.stop() }
  func makeView(_ arguments: Any?) -> NSView {
    guard let p = arguments as? [String: Any], let id = (p["id"] as? NSNumber)?.int64Value,
      let renderer = renderers[id]
    else { return NSView() }
    let view = CadMetalView(frame: .zero, device: renderer.device)
    view.renderer = renderer
    view.onDispose = { [weak self] in self?.remove(id) }
    renderer.attach(view)
    return view
  }
}

private final class CadMetalViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: CadMetalPlugin?
  init(_ plugin: CadMetalPlugin) { self.plugin = plugin }
  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    plugin?.makeView(args) ?? NSView()
  }
}

private final class CadMetalView: MTKView {
  var renderer: MetalViewportRenderer?
  var onDispose: (() -> Void)?
  override var acceptsFirstResponder: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  deinit { onDispose?() }
}
