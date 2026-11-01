import Carbon
import Cocoa
import FlutterMacOS

/// Tells the app to start a new question when the global shortcut is pressed.
private var quickAsk: FlutterMethodChannel?

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    quickAsk = FlutterMethodChannel(name: "herapp/quick", binaryMessenger: flutterViewController.engine.binaryMessenger)
    registerQuickAsk()

    super.awakeFromNib()
  }

  /// ⌥Space from any app brings the window forward on a new question.
  private func registerQuickAsk() {
    var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
      NSApp.activate(ignoringOtherApps: true)
      if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
      }
      quickAsk?.invokeMethod("ask", arguments: nil)
      return noErr
    }, 1, &pressed, nil, nil)
    var ref: EventHotKeyRef?
    // taken by another app, it is simply not ours
    RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), EventHotKeyID(signature: OSType(0x4845_524D), id: 1), GetApplicationEventTarget(), 0, &ref)
  }
}
