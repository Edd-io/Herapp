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
    quickAsk?.setMethodCallHandler { call, result in
      switch call.method {
      case "handoff":
        Handoff.shared.offer(call.arguments as? [String: Any])
        result(nil)
      case "continued": result(Handoff.shared.take { quickAsk?.invokeMethod("continue", arguments: $0) })
      default: result(FlutterMethodNotImplemented)
      }
    }
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

/// The open conversation, offered to the user's other Apple devices; one they hand over opens here.
final class Handoff {
  static let shared = Handoff()
  static let type = "com.edd-io.herapp.chat"
  private var activity: NSUserActivity?
  private var waiting: [String: Any]?
  private var open: (([String: Any]) -> Void)?

  /// Offers `{session, title, server}`, or nothing with nil.
  func offer(_ chat: [String: Any]?) {
    activity?.invalidate()
    activity = nil
    guard let chat else { return }
    let a = NSUserActivity(activityType: Self.type)
    a.title = chat["title"] as? String
    a.userInfo = chat
    a.isEligibleForHandoff = true
    a.becomeCurrent()
    activity = a
  }

  /// What was handed over before the chat listened; later ones go to [open].
  func take(_ open: @escaping ([String: Any]) -> Void) -> [String: Any]? {
    self.open = open
    defer { waiting = nil }
    return waiting
  }

  func received(_ a: NSUserActivity) -> Bool {
    guard a.activityType == Self.type, let chat = a.userInfo as? [String: Any] else { return false }
    if let open { open(chat) } else { waiting = chat }
    return true
  }
}
