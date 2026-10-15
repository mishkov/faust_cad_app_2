import Cocoa
import FlutterMacOS
import Metal

class MainFlutterWindow: NSWindow {
  private var benchmarkDiagnostics: FlutterMethodChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    benchmarkDiagnostics = FlutterMethodChannel(
      name: "cad.benchmark.environment", binaryMessenger: flutterViewController.engine.binaryMessenger)
    benchmarkDiagnostics?.setMethodCallHandler { call, result in
      guard call.method == "read" else { result(FlutterMethodNotImplemented); return }
      let session = CGSessionCopyCurrentDictionary() as? [String: Any]
      result([
        "foreground": NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
        "session_available": session != nil,
        "session_locked": session?["CGSSessionScreenIsLocked"] as? Bool ?? false,
        "on_console": session?[kCGSessionOnConsoleKey as String] as? Bool ?? false,
        "gpu": MTLCreateSystemDefaultDevice()?.name ?? "unknown",
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
      ])
    }

    super.awakeFromNib()
  }
}
