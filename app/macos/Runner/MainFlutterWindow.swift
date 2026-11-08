import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var statusItem: NSStatusItem?
  /// Keeps App Nap off while waiting for calls (see updateStatus).
  private var activity: NSObjectProtocol?
  private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
  // In the app's language once it sends its first status
  private let openItem = NSMenuItem(title: "Open Sippier", action: nil, keyEquivalent: "")
  private let quitItem = NSMenuItem(
    title: "Quit Sippier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "sippier/platform",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startRinging":
        self?.showWindow()
        NSApp.requestUserAttention(.criticalRequest)
        result(nil)
      case "stopRinging":
        result(nil)
      case "updateStatus":
        let args = call.arguments as? [String: Any] ?? [:]
        self?.updateStatus(
          text: args["text"] as? String ?? "",
          registered: args["registered"] as? Bool ?? false,
          openLabel: args["openLabel"] as? String,
          quitLabel: args["quitLabel"] as? String)
        self?.setWaitingForCalls(
          (args["background"] as? Bool ?? false) || (args["inCall"] as? Bool ?? false))
        result(nil)
      case "openUrl":
        if let url = URL(string: call.arguments as? String ?? "") {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      case "launchAtLogin":
        result(Self.launchAtLogin())
      case "setLaunchAtLogin":
        result(Self.setLaunchAtLogin(call.arguments as? Bool ?? false))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    delegate = self
    setUpStatusItem()

    // The window isn't visible at launch (MainMenu.xib): it opens once the
    // app has launched, unless that was at login, where Sippier starts in
    // the menu bar. Only the launch's own event says so.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: nil
    ) { [weak self] _ in
      let event = NSAppleEventManager.shared().currentAppleEvent
      let atLogin =
        event?.eventID == kAEOpenApplication
        && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
          == keyAELaunchedAsLogInItem
      if atLogin {
        NSApp.setActivationPolicy(.accessory)
      } else {
        self?.showWindow()
      }
    }

    super.awakeFromNib()
  }

  /// Nil before macOS 13, whose login items the app can't set on its own.
  private static func launchAtLogin() -> Bool? {
    guard #available(macOS 13, *) else { return nil }
    return SMAppService.mainApp.status == .enabled
  }

  private static func setLaunchAtLogin(_ on: Bool) -> Bool? {
    guard #available(macOS 13, *) else { return nil }
    let service = SMAppService.mainApp
    do {
      if on {
        try service.register()
      } else {
        try service.unregister()
      }
    } catch {
      NSLog("Sippier: login item: \(error)")
    }
    // Turned off under Login Items in System Settings: only the user can
    // turn it back on there
    if on, service.status == .requiresApproval {
      SMAppService.openSystemSettingsLoginItems()
    }
    return service.status == .enabled
  }

  func showWindow() {
    NSApp.setActivationPolicy(.regular)
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // The window isn't released when closed, so the app keeps running in the
  // menu bar, without a Dock icon.
  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  private func setUpStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = Self.icon(registered: false)

    let menu = NSMenu()
    statusLine.isEnabled = false
    menu.addItem(statusLine)
    menu.addItem(.separator())
    openItem.action = #selector(openFromMenu)
    openItem.target = self
    menu.addItem(openItem)
    menu.addItem(quitItem)
    item.menu = menu
    statusItem = item
  }

  private func updateStatus(
    text: String, registered: Bool, openLabel: String?, quitLabel: String?
  ) {
    statusLine.title = text
    if let open = openLabel { openItem.title = open }
    if let quit = quitLabel { quitItem.title = quit }
    statusItem?.button?.image = Self.icon(registered: registered)
    statusItem?.button?.toolTip = "Sippier: \(text)"
  }

  /// App Nap throttles the timers of an app without a visible window, so
  /// registration refreshes and keep-alives would run late while Sippier
  /// sits in the menu bar. Idle system sleep stays allowed; the core
  /// unregisters before the Mac sleeps.
  private func setWaitingForCalls(_ waiting: Bool) {
    if waiting, activity == nil {
      activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Waiting for calls")
    } else if !waiting, let a = activity {
      ProcessInfo.processInfo.endActivity(a)
      activity = nil
    }
  }

  @objc private func openFromMenu() {
    showWindow()
  }

  // The Sippier mark from the asset catalog: filled while registered,
  // outlined while not.
  private static func icon(registered: Bool) -> NSImage? {
    let image = NSImage(named: registered ? "StatusIcon" : "StatusIconOff")
    image?.size = NSSize(width: 18, height: 18)
    image?.isTemplate = true
    image?.accessibilityDescription = "Sippier"
    return image
  }
}
