import AppKit
import ServiceManagement
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let client = MailpitClient()
    private let notifier = Notifier()

    private var connected = false
    private var unread = 0
    private var total = 0
    private var recent: [MailpitMessage] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        rebuildMenu()
        updateStatusButton()

        notifier.requestAuthorization()
        client.delegate = self
        client.start()
    }

    // MARK: Status item

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let symbol = !connected ? "envelope.badge.shield.half.filled" : (unread > 0 ? "envelope.badge.fill" : "envelope")
        let description = connected ? "Mailpit, \(unread) unread" : "Mailpit disconnected"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.title = (connected && unread > 0) ? " \(unread)" : ""
        button.toolTip = description
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let open = NSMenuItem(title: "Open Mailpit", action: #selector(openMailpit), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        if recent.isEmpty {
            let empty = NSMenuItem(title: connected ? "No messages" : "Unable to reach Mailpit", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for mail in recent {
                let item = NSMenuItem(title: "", action: #selector(openMessage(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = mail.id
                item.attributedTitle = menuTitle(for: mail)
                item.toolTip = mail.snippet
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        let markRead = NSMenuItem(title: "Mark All as Read", action: #selector(markAllRead), keyEquivalent: "")
        markRead.target = self
        markRead.isEnabled = unread > 0
        menu.addItem(markRead)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())

        let url = NSMenuItem(title: "Mailpit URL…", action: #selector(editURL), keyEquivalent: ",")
        url.target = self
        menu.addItem(url)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Mailpit Menubar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private var statusLine: String {
        guard connected else { return "Mailpit: not connected (\(Settings.baseURL.host ?? "?"))" }
        return "Mailpit: \(total) message\(total == 1 ? "" : "s"), \(unread) unread"
    }

    private func menuTitle(for mail: MailpitMessage) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let bold = NSFont.boldSystemFont(ofSize: font.pointSize)
        let subject = String(mail.subjectDisplay.prefix(60))
        let result = NSMutableAttributedString(
            string: (mail.read ? "" : "● ") + subject,
            attributes: [.font: mail.read ? font : bold]
        )
        result.append(NSAttributedString(
            string: "  \(mail.fromDisplay)",
            attributes: [.font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        return result
    }

    // MARK: Actions

    @objc private func openMailpit() {
        NSWorkspace.shared.open(Settings.baseURL)
    }

    @objc private func openMessage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(Settings.messageURL(id: id))
    }

    @objc private func markAllRead() {
        Task { await client.markAllRead() }
    }

    @objc private func refresh() {
        client.restart()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            presentError("Could not change Launch at Login", error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func editURL() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mailpit URL"
        alert.informativeText = "The address of the Mailpit web UI, e.g. http://localhost:8025"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = Settings.baseURLString
        field.placeholderString = Settings.defaultBaseURL
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Settings.baseURLString = value.isEmpty ? Settings.defaultBaseURL : value
        recent = []
        connected = false
        rebuildMenu()
        updateStatusButton()
        client.restart()
    }

    private func presentError(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}

// MARK: - MailpitClientDelegate

extension AppDelegate: MailpitClientDelegate {
    func client(_ client: MailpitClient, connectionChanged connected: Bool) {
        self.connected = connected
        rebuildMenu()
        updateStatusButton()
    }

    func client(_ client: MailpitClient, receivedNew message: MailpitMessage) {
        recent.insert(message, at: 0)
        if recent.count > 12 { recent.removeLast(recent.count - 12) }
        total += 1
        unread += 1
        rebuildMenu()
        updateStatusButton()
        notifier.notify(message)
    }

    func client(_ client: MailpitClient, receivedStats stats: MailpitStats) {
        total = stats.total
        unread = stats.unread
        // Stats arrive on connect and after every change, so a mismatch means our list is stale.
        rebuildMenu()
        updateStatusButton()
    }

    func client(_ client: MailpitClient, recentMessages messages: [MailpitMessage], newSinceLastSync: [MailpitMessage]) {
        recent = messages
        rebuildMenu()
        updateStatusButton()
        // Anything that slipped past while the socket was down gets a notification too.
        if newSinceLastSync.count > 3 {
            notifier.notifySummary(count: newSinceLastSync.count)
        } else {
            newSinceLastSync.reversed().forEach { notifier.notify($0) }
        }
    }
}

// MARK: - Notifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    nonisolated private static let messageIDKey = "messageID"

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            log.info("notification authorisation granted=\(granted) error=\(error.map { String(describing: $0) } ?? "none", privacy: .public)")
        }
    }

    func notify(_ mail: MailpitMessage) {
        let content = UNMutableNotificationContent()
        content.title = mail.fromDisplay
        content.subtitle = mail.subjectDisplay
        content.body = mail.snippet ?? ""
        content.sound = .default
        content.threadIdentifier = "mailpit"
        content.userInfo = [Self.messageIDKey: mail.id]
        let request = UNNotificationRequest(identifier: "mailpit-\(mail.id)", content: content, trigger: nil)
        center.add(request) { error in
            if let error { log.error("notification failed for \(mail.id, privacy: .public): \(String(describing: error), privacy: .public)") }
            else { log.info("notification posted for \(mail.id, privacy: .public)") }
        }
    }

    func notifySummary(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Mailpit"
        content.body = "\(count) new messages arrived"
        content.sound = .default
        content.threadIdentifier = "mailpit"
        let request = UNNotificationRequest(identifier: "mailpit-summary-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        center.add(request) { error in
            if let error { log.error("summary notification failed: \(String(describing: error), privacy: .public)") }
        }
    }

    // Show banners even while the app is "active" (it never really is, being a menubar app).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo[Self.messageIDKey] as? String
        await MainActor.run {
            let url = id.map { Settings.messageURL(id: $0) } ?? Settings.baseURL
            NSWorkspace.shared.open(url)
        }
    }
}
