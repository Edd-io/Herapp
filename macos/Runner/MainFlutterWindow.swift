import Carbon
import Cocoa
import FlutterMacOS
import UserNotifications

/// Tells the app to start a new question when the global shortcut is pressed.
private var quickAsk: FlutterMethodChannel?

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // one surface up to the traffic lights, as Notes or Messages: no title bar strip above the app
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden

    RegisterGeneratedPlugins(registry: flutterViewController)
    quickAsk = FlutterMethodChannel(name: "herapp/quick", binaryMessenger: flutterViewController.engine.binaryMessenger)
    quickAsk?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "handoff":
        Handoff.shared.offer(call.arguments as? [String: Any])
        result(nil)
      case "continued": result(Handoff.shared.take { quickAsk?.invokeMethod("continue", arguments: $0) })
      case "fullScreen":
        if let self, styleMask.contains(.fullScreen) != (call.arguments as? Bool ?? false) { toggleFullScreen(nil) }
        result(nil)
      case "notifyAllow":
        Notifier.shared.allow()
        result(nil)
      case "notify":
        Notifier.shared.post(call.arguments as? [String: Any])
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    registerQuickAsk()
    Notifier.shared.listen()

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

/// A reply done while the app is out of sight, told by the system; a tap opens its chat (as Handoff does).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
  static let shared = Notifier()

  /// Takes the taps from launch on: one that opens the app comes before the chat listens.
  func listen() { UNUserNotificationCenter.current().delegate = self }

  func allow() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }

  /// Posts `{title, body, session, server}`, grouped by chat.
  func post(_ args: [String: Any]?) {
    guard let args else { return }
    let content = UNMutableNotificationContent()
    content.title = args["title"] as? String ?? "Herapp"
    content.body = args["body"] as? String ?? ""
    content.sound = .default
    content.threadIdentifier = args["session"] as? String ?? ""
    content.userInfo = args
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void
  ) { done([.banner, .sound]) }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void
  ) {
    let chat = response.notification.request.content.userInfo as? [String: Any] ?? [:]
    let a = NSUserActivity(activityType: Handoff.type)
    a.userInfo = chat
    _ = Handoff.shared.received(a)
    done()
  }
}
