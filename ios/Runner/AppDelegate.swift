import AppIntents
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    QuickAsk.shared.connect(engineBridge.applicationRegistrar.messenger())
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
