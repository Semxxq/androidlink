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
final class StatusBarController: NSObject, NSMenuDelegate {
  static let shared = StatusBarController()

  private var item: NSStatusItem?
  private var channel: FlutterMethodChannel?
  private weak var window: NSWindow?
  private let card = PhoneCardView(frame: NSRect(x: 0, y: 0, width: 300, height: 124))
  private var actionItems: [NSMenuItem] = []

  func attach(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.window = window
    let ch = FlutterMethodChannel(name: "androidlink/tray", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let pb = NSPasteboard.general
      switch call.method {
      case "clipCount":
        result(pb.changeCount); return
      case "clipImage":
        // Image only when there is no text (avoid hijacking rich-text copies).
        if pb.string(forType: .string) != nil { result(nil); return }
        guard let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { result(nil); return }
        let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        result(jpg.map { FlutterStandardTypedData(bytes: $0) }); return
      case "setClipImage":
        if let d = (call.arguments as? FlutterStandardTypedData)?.data, let img = NSImage(data: d) {
          pb.clearContents(); pb.writeObjects([img])
        }
        result(pb.changeCount); return
      default: break
      }
      if call.method == "update", let a = call.arguments as? [String: Any] {
        self.update(a)
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
    let cardItem = NSMenuItem()
    cardItem.view = card
    menu.delegate = self
    menu.addItem(cardItem)
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
    update([:])
  }

  private func makeItem(_ title: String, _ id: String, _ symbol: String) -> NSMenuItem {
    let m = NSMenuItem(title: title, action: #selector(onAction(_:)), keyEquivalent: "")
    m.target = self
    m.representedObject = id
    m.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    return m
  }

  private func update(_ a: [String: Any]) {
    let connected = a["connected"] as? Bool ?? false
    item?.button?.image = NSImage(
      systemSymbolName: connected ? "iphone" : "iphone.slash", accessibilityDescription: "AndroidLink")
    card.apply(connected: connected,
               name: a["title"] as? String ?? "",
               battery: (a["battery"] as? NSNumber)?.intValue ?? -1,
               charging: (a["charging"] as? NSNumber)?.boolValue ?? false,
               unread: (a["unread"] as? NSNumber)?.intValue ?? 0,
               notifs: (a["notifs"] as? NSNumber)?.intValue ?? 0,
               missed: (a["missed"] as? NSNumber)?.intValue ?? 0,
               syncing: (a["syncing"] as? NSNumber)?.boolValue ?? false)
    actionItems.forEach { $0.isEnabled = connected }
  }

  func menuWillOpen(_ menu: NSMenu) { card.needsDisplay = true }


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

// ── Menu bar phone card (plain AppKit: reliable inside NSMenu) ─────────

final class PhoneCardView: NSView {
  private let tile = NSView()
  private let phone = NSImageView()
  private let dot = NSView()
  private let name = NSTextField(labelWithString: "Телефон не подключён")
  private let batteryIcon = NSImageView()
  private let status = NSTextField(labelWithString: "Ожидание подключения…")
  private var stats: [(NSTextField, NSImageView)] = []

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true

    tile.wantsLayer = true
    tile.layer?.cornerRadius = 10
    tile.frame = NSRect(x: 14, y: frame.height - 54, width: 40, height: 40)
    addSubview(tile)
    phone.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 20, weight: .medium))
    phone.contentTintColor = .white
    phone.frame = tile.bounds
    tile.addSubview(phone)

    dot.wantsLayer = true
    dot.layer?.cornerRadius = 6
    dot.layer?.borderWidth = 2
    dot.layer?.borderColor = NSColor.windowBackgroundColor.cgColor
    dot.frame = NSRect(x: 45, y: frame.height - 58, width: 12, height: 12)
    addSubview(dot)

    name.font = .systemFont(ofSize: 13, weight: .semibold)
    name.lineBreakMode = .byTruncatingTail
    name.frame = NSRect(x: 66, y: frame.height - 34, width: 220, height: 18)
    addSubview(name)

    batteryIcon.frame = NSRect(x: 66, y: frame.height - 53, width: 22, height: 14)
    addSubview(batteryIcon)
    status.font = .systemFont(ofSize: 11)
    status.textColor = .secondaryLabelColor
    status.frame = NSRect(x: 66, y: frame.height - 54, width: 220, height: 15)
    addSubview(status)

    let items: [(String, String, NSColor)] = [
      ("message.fill", "SMS", .systemBlue),
      ("bell.fill", "Уведомл.", .systemOrange),
      ("phone.down.fill", "Пропущ.", .systemRed),
    ]
    let w: CGFloat = (frame.width - 28 - 16) / 3
    for (i, it) in items.enumerated() {
      let box = NSView(frame: NSRect(x: 14 + CGFloat(i) * (w + 8), y: 10, width: w, height: 46))
      box.wantsLayer = true
      box.layer?.cornerRadius = 8
      box.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
      let icon = NSImageView(frame: NSRect(x: w / 2 - 22, y: 22, width: 16, height: 16))
      icon.image = NSImage(systemSymbolName: it.0, accessibilityDescription: nil)
      icon.contentTintColor = it.2
      let n = NSTextField(labelWithString: "0")
      n.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
      n.frame = NSRect(x: w / 2 - 4, y: 21, width: w / 2, height: 18)
      let l = NSTextField(labelWithString: it.1)
      l.font = .systemFont(ofSize: 10)
      l.textColor = .secondaryLabelColor
      l.alignment = .center
      l.frame = NSRect(x: 0, y: 5, width: w, height: 14)
      [icon, n, l].forEach { box.addSubview($0) }
      addSubview(box)
      stats.append((n, icon))
    }
    apply(connected: false, name: "", battery: -1, charging: false, unread: 0, notifs: 0, missed: 0, syncing: false)
  }

  required init?(coder: NSCoder) { fatalError() }

  func apply(connected: Bool, name n: String, battery: Int, charging: Bool,
             unread: Int, notifs: Int, missed: Int, syncing: Bool) {
    let grad = CAGradientLayer()
    grad.frame = tile.bounds
    grad.cornerRadius = 10
    grad.startPoint = CGPoint(x: 0, y: 1)
    grad.endPoint = CGPoint(x: 1, y: 0)
    grad.colors = connected
      ? [NSColor(red: 0.2, green: 0.56, blue: 1, alpha: 1).cgColor, NSColor(red: 0.45, green: 0.3, blue: 0.95, alpha: 1).cgColor]
      : [NSColor.systemGray.cgColor, NSColor.systemGray.withAlphaComponent(0.6).cgColor]
    tile.layer?.sublayers?.filter { $0 is CAGradientLayer }.forEach { $0.removeFromSuperlayer() }
    tile.layer?.insertSublayer(grad, at: 0)
    dot.layer?.backgroundColor = (connected ? NSColor.systemGreen : NSColor.systemGray).cgColor

    name.stringValue = connected ? (n.isEmpty ? "Телефон" : n) : "Телефон не подключён"
    let lvl = max(battery, 0)
    let sym = charging ? "battery.100.bolt"
      : lvl < 13 ? "battery.0" : lvl < 38 ? "battery.25" : lvl < 63 ? "battery.50" : lvl < 88 ? "battery.75" : "battery.100"
    batteryIcon.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)
    batteryIcon.contentTintColor = charging ? .systemGreen : (lvl <= 20 ? .systemRed : .labelColor)
    batteryIcon.isHidden = !connected
    status.frame.origin.x = connected ? 92 : 66
    status.stringValue = connected ? "\(lvl)% · \(syncing ? "синхронизация…" : "подключён")" : "Ожидание подключения…"

    for (i, v) in [unread, notifs, missed].enumerated() { stats[i].0.stringValue = "\(v)" }
    needsDisplay = true
  }
}
