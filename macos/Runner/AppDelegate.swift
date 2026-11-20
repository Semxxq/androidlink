import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Keep running in the menu bar when the window is closed (like Continuity).
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    StatusBarController.shared.showWindow()
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// Menu bar item: connection + battery at a glance, quick actions.
/// Dart → Swift: "update" {connected, title, subtitle}
/// Swift → Dart: "action" {id: ring | clipboard | sendFile}
final class StatusBarController: NSObject {
  static let shared = StatusBarController()

  private var item: NSStatusItem?
  private var channel: FlutterMethodChannel?
  private weak var window: NSWindow?
  private let titleItem = NSMenuItem(title: "Телефон не подключён", action: nil, keyEquivalent: "")
  private let subtitleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private var actionItems: [NSMenuItem] = []

  func attach(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.window = window
    let ch = FlutterMethodChannel(name: "androidlink/tray", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      if call.method == "update", let a = call.arguments as? [String: Any] {
        self.update(connected: a["connected"] as? Bool ?? false,
                    title: a["title"] as? String ?? "",
                    subtitle: a["subtitle"] as? String ?? "")
      }
      result(nil)
    }
    channel = ch
    setupItem()
  }

  private func setupItem() {
    let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    it.button?.image = NSImage(systemSymbolName: "iphone.slash", accessibilityDescription: "AndroidLink")
    let menu = NSMenu()
    titleItem.isEnabled = false
    subtitleItem.isEnabled = false
    subtitleItem.isHidden = true
    menu.addItem(titleItem)
    menu.addItem(subtitleItem)
    menu.addItem(.separator())
    actionItems = [
      makeItem("Найти телефон", "ring", "speaker.wave.3"),
      makeItem("Отправить буфер на телефон", "clipboard", "doc.on.clipboard"),
      makeItem("Отправить файл…", "sendFile", "paperplane"),
    ]
    actionItems.forEach { menu.addItem($0) }
    menu.addItem(.separator())
    let open = NSMenuItem(title: "Открыть AndroidLink", action: #selector(openWindow), keyEquivalent: "o")
    open.target = self
    menu.addItem(open)
    menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    it.menu = menu
    item = it
    update(connected: false, title: "", subtitle: "")
  }

  private func makeItem(_ title: String, _ id: String, _ symbol: String) -> NSMenuItem {
    let m = NSMenuItem(title: title, action: #selector(onAction(_:)), keyEquivalent: "")
    m.target = self
    m.representedObject = id
    m.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    return m
  }

  private func update(connected: Bool, title: String, subtitle: String) {
    item?.button?.image = NSImage(
      systemSymbolName: connected ? "iphone" : "iphone.slash", accessibilityDescription: "AndroidLink")
    titleItem.title = connected ? title : "Телефон не подключён"
    subtitleItem.title = subtitle
    subtitleItem.isHidden = !connected || subtitle.isEmpty
    actionItems.forEach { $0.isEnabled = connected }
  }

  @objc private func onAction(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    if id == "sendFile" { showWindow() }
    channel?.invokeMethod("action", arguments: ["id": id])
  }

  @objc private func openWindow() { showWindow() }

  func showWindow() {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}
