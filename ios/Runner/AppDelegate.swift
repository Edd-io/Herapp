import AppIntents
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    Notifier.shared.listen()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    QuickAsk.shared.connect(engineBridge.applicationRegistrar.messenger())
    engineBridge.pluginRegistry.registrar(forPlugin: "Handoff")?.addSceneDelegate(Handoff.shared)
  }
}

/// Questions asked through Siri or Shortcuts, handed to the app once its chat listens.
final class QuickAsk {
  static let shared = QuickAsk()
  private var channel: FlutterMethodChannel?
  private var waiting: [String] = []
  private var ready = false

  func connect(_ messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "herapp/quick", binaryMessenger: messenger)
    // the chat says when it listens and takes what was asked before; it collects shares as it comes forward
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "ready":
        self.ready = true
        result(self.waiting)
        self.waiting = []
      case "shared": result(Self.takeShared())
      case "handoff":
        Handoff.shared.offer(call.arguments as? [String: Any])
        result(nil)
      case "continued":
        result(Handoff.shared.take { [weak self] in self?.channel?.invokeMethod("continue", arguments: $0) })
      case "notifyAllow":
        Notifier.shared.allow()
        result(nil)
      case "notify":
        Notifier.shared.post(call.arguments as? [String: Any])
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  /// What the share extension left in the app group's inbox, emptied as it is read:
  /// one `{text, files: [{name, bytes}]}` per share, oldest first.
  static func takeShared() -> [[String: Any]] {
    let fm = FileManager.default
    guard let inbox = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.edd-io.herapp")?
      .appendingPathComponent("Inbox", isDirectory: true),
      let shares = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.creationDateKey])
    else { return [] }
    let made = { (u: URL) in (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
    return shares.sorted { made($0) < made($1) }.map { share in
      defer { try? fm.removeItem(at: share) }
      let files = (try? fm.contentsOfDirectory(at: share.appendingPathComponent("files"), includingPropertiesForKeys: nil)) ?? []
      return [
        "text": (try? String(contentsOf: share.appendingPathComponent("text.txt"), encoding: .utf8)) ?? "",
        "files": files.compactMap { f in
          (try? Data(contentsOf: f)).map { ["name": f.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: $0)] }
        },
      ]
    }
  }

  func ask(_ question: String) {
    if ready, let channel { channel.invokeMethod("ask", arguments: question) } else { waiting.append(question) }
  }
}

/// The open conversation, offered to the user's other Apple devices; one they hand over opens here.
final class Handoff: NSObject, FlutterSceneLifeCycleDelegate {
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

  func received(_ a: NSUserActivity?) -> Bool {
    guard let a, a.activityType == Self.type, let chat = a.userInfo as? [String: Any] else { return false }
    if let open { open(chat) } else { waiting = chat }
    return true
  }

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions?) -> Bool {
    received(options?.userActivities.first)
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool { received(userActivity) }
}

@available(iOS 16, *)
struct AskHermes: AppIntent {
  static var title: LocalizedStringResource = "Ask Hermes"
  static var description = IntentDescription("Opens Hermes on a new chat and sends your question.")
  static var openAppWhenRun = true

  @Parameter(title: "Question", requestValueDialog: "What do you want to ask?")
  var question: String

  @MainActor
  func perform() async throws -> some IntentResult {
    QuickAsk.shared.ask(question)
    return .result()
  }
}

@available(iOS 16, *)
struct HermesShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: AskHermes(), phrases: ["Ask \(.applicationName)", "Demande à \(.applicationName)"])
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
  ) {
    if #available(iOS 14, *) { done([.banner, .sound]) } else { done([.alert, .sound]) }
  }

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
