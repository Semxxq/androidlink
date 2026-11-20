import Cocoa
import FlutterMacOS
import SwiftUI

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
  private let card = PhoneCardModel()
  private var cardHost: NSHostingView<PhoneCardView>?
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
    let host = NSHostingView(rootView: PhoneCardView(m: card))
    host.frame = NSRect(x: 0, y: 0, width: 300, height: 132)
    cardItem.view = host
    cardHost = host
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
    card.connected = connected
    card.name = a["title"] as? String ?? ""
    card.battery = a["battery"] as? Int ?? -1
    card.charging = a["charging"] as? Bool ?? false
    card.unread = a["unread"] as? Int ?? 0
    card.notifs = a["notifs"] as? Int ?? 0
    card.missed = a["missed"] as? Int ?? 0
    card.syncing = a["syncing"] as? Bool ?? false
    actionItems.forEach { $0.isEnabled = connected }
    refreshCard()
  }

  private func refreshCard() {
    // SwiftUI inside an NSMenu does not reliably observe changes; push a fresh snapshot.
    cardHost?.rootView = PhoneCardView(m: card.snapshot())
    cardHost?.needsDisplay = true
  }

  func menuWillOpen(_ menu: NSMenu) { refreshCard() }


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

// ── Menu bar phone card ─────────────────────────────────────────────────

final class PhoneCardModel: ObservableObject {
  @Published var connected = false
  @Published var name = ""
  @Published var battery = -1
  @Published var charging = false
  @Published var unread = 0
  @Published var notifs = 0
  @Published var missed = 0
  @Published var syncing = false

  func snapshot() -> PhoneCardModel {
    let c = PhoneCardModel()
    c.connected = connected; c.name = name; c.battery = battery; c.charging = charging
    c.unread = unread; c.notifs = notifs; c.missed = missed; c.syncing = syncing
    return c
  }
}

struct PhoneCardView: View {
  @ObservedObject var m: PhoneCardModel

  private var batteryColor: Color {
    if m.charging { return .green }
    return m.battery >= 0 && m.battery <= 20 ? .red : .primary
  }

  private var batterySymbol: String {
    if m.charging { return "battery.100.bolt" }
    switch m.battery {
    case ..<0: return "battery.0"
    case ..<13: return "battery.0"
    case ..<38: return "battery.25"
    case ..<63: return "battery.50"
    case ..<88: return "battery.75"
    default: return "battery.100"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        ZStack(alignment: .bottomTrailing) {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: m.connected ? [Color(red: 0.2, green: 0.55, blue: 1), Color(red: 0.45, green: 0.3, blue: 0.95)]
                                                     : [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: "iphone").font(.system(size: 20, weight: .medium)).foregroundColor(.white))
          Circle().fill(m.connected ? Color.green : Color.gray)
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
            .offset(x: 3, y: 3)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(m.connected ? (m.name.isEmpty ? "Телефон" : m.name) : "Телефон не подключён")
            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
          HStack(spacing: 5) {
            if m.connected {
              Image(systemName: batterySymbol).foregroundColor(batteryColor)
              Text(m.battery >= 0 ? "\(m.battery)%" : "0%").foregroundColor(.secondary)
              if m.syncing {
                Text("· синхронизация…").foregroundColor(.secondary)
              } else {
                Text("· подключён").foregroundColor(.secondary)
              }
            } else {
              Text("Ожидание подключения…").foregroundColor(.secondary)
            }
          }.font(.system(size: 11))
        }
        Spacer(minLength: 0)
      }
      HStack(spacing: 8) {
        stat("message.fill", m.unread, "SMS", .blue)
        stat("bell.fill", m.notifs, "Уведомл.", .orange)
        stat("phone.down.fill", m.missed, "Пропущ.", .red)
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .frame(width: 300, height: 132, alignment: .topLeading)
  }

  private func stat(_ symbol: String, _ n: Int, _ label: String, _ tint: Color) -> some View {
    VStack(spacing: 3) {
      HStack(spacing: 4) {
        Image(systemName: symbol).font(.system(size: 11)).foregroundColor(tint)
        Text("\(n)").font(.system(size: 14, weight: .semibold, design: .rounded))
      }
      Text(label).font(.system(size: 10)).foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
  }
}
