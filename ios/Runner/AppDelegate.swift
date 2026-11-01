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
    // the chat says when it listens and takes what was asked before
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "ready" else { return result(FlutterMethodNotImplemented) }
      self.ready = true
      result(self.waiting)
      self.waiting = []
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
