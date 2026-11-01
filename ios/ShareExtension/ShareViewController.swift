import Social
import UIKit
import UniformTypeIdentifiers

/// "Share → Hermes": keeps what was shared (text, links, photos, files) in the app group's inbox,
/// then opens the app, which starts a new chat with it.
class ShareViewController: SLComposeServiceViewController {
  static let group = "group.com.edd-io.herapp"

  override func isContentValid() -> Bool { true }

  override func didSelectPost() {
    Task {
      await save()
      open(URL(string: "herapp://share")!)
      extensionContext?.completeRequest(returningItems: nil)
    }
  }

  override func configurationItems() -> [Any]! { [] }

  /// One share is one folder: `text.txt` (the comment, texts and links), and the files as they were named.
  private func save() async {
    guard let inbox = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group)?
      .appendingPathComponent("Inbox/\(UUID().uuidString)", isDirectory: true)
    else { return }
    try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    var texts = [contentText ?? ""]
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    for p in providers {
      if p.hasItemConformingToTypeIdentifier(UTType.url.identifier), !p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
        let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL
      {
        texts.append(url.absoluteString)
      } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
        let text = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
      {
        texts.append(text)
      } else if let type = p.registeredTypeIdentifiers.first {
        await copy(p, type, into: inbox)
      }
    }
    let text = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    try? text.write(to: inbox.appendingPathComponent("text.txt"), atomically: true, encoding: .utf8)
  }

  private func copy(_ p: NSItemProvider, _ type: String, into folder: URL) async {
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      _ = p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
        if let url {
          let ext = url.pathExtension
          let name = p.suggestedName.map { ext.isEmpty || $0.hasSuffix(".\(ext)") ? $0 : "\($0).\(ext)" } ?? url.lastPathComponent
          let to = folder.appendingPathComponent("files", isDirectory: true)
          try? FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
          try? FileManager.default.copyItem(at: url, to: to.appendingPathComponent(name))
        }
        done.resume()
      }
    }
  }

  /// An extension can't open its app directly: the app object up the responder chain can, called by name
  /// since its `open` is off limits to extension code.
  private func open(_ url: URL) {
    typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
    let sel = NSSelectorFromString("openURL:options:completionHandler:")
    var r: UIResponder? = self
    while let next = r {
      if let app = next as? UIApplication, app.responds(to: sel) {
        unsafeBitCast(app.method(for: sel), to: Open.self)(app, sel, url as NSURL, [:], nil)
        return
      }
      r = next.next
    }
  }
}
