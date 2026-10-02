import AppKit
import SwiftUI
import YTSubsCore

@main
struct YTSubsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var snapshot: ChannelSnapshot?
    @Published var lastAttemptFailed = false
    @Published var refreshing = false
    @Published var nextCheck: Date?
    var channelID = UserDefaults.standard.string(forKey: "channelID") ?? ""
    var interval = max(60, UserDefaults.standard.double(forKey: "interval"))
    private var key = ""
    private var item: NSStatusItem!
    private var timer: Timer?
    private var request: Task<Void, Never>?
    private var flash: Task<Void, Never>?
    private var generation = 0
    private var settingsWindow: NSWindow?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        key = Keychain.read()
        if let data = UserDefaults.standard.data(forKey: "snapshot"),
           let cached = try? JSONDecoder().decode(ChannelSnapshot.self, from: data), cached.id == channelID,
           Date().timeIntervalSince(cached.fetchedAt) < 30 * 86400 { snapshot = cached }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: Dashboard(model: self))
        render()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        if channelID.isEmpty || key.isEmpty { showSettings() } else { refresh() }
    }
    @objc func woke() { if nextCheck == nil || nextCheck! <= Date() { refresh() } }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    func render(color: NSColor = .labelColor) {
        let title = snapshot.map { SubscriberFormat.string($0.count) } ?? "—"
        item.button?.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "YouTube subscribers")
        item.button?.imagePosition = .imageLeading
        item.button?.attributedTitle = NSAttributedString(string: " " + title, attributes: [.foregroundColor: color, .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)])
        item.button?.toolTip = snapshot.map { "\($0.title): \($0.count.formatted()) subscribers • updated \($0.fetchedAt.formatted())" } ?? "YT Subs — open settings to connect a channel"
    }
    func animate(increased: Bool) {
        flash?.cancel()
        flash = Task { @MainActor in
            for _ in 0..<3 {
                guard !Task.isCancelled else { return }
                render(color: increased ? .systemGreen : .systemRed)
                try? await Task.sleep(for: .milliseconds(333))
                guard !Task.isCancelled else { return }
                render()
                try? await Task.sleep(for: .milliseconds(333))
            }
        }
    }
    func refresh() {
        guard !refreshing, !channelID.isEmpty, !key.isEmpty else { return }
        timer?.invalidate(); nextCheck = nil
        refreshing = true
        let currentGeneration = generation
        let channel = channelID, apiKey = key
        request = Task { @MainActor in
            var failed = false
            do {
                let result = try await YouTubeAPI.fetch(channelID: channel, key: apiKey)
                guard !Task.isCancelled, generation == currentGeneration else { return }
                let previous = snapshot?.count
                snapshot = result
                lastAttemptFailed = false
                if let data = try? JSONEncoder().encode(result) { UserDefaults.standard.set(data, forKey: "snapshot") }
                render()
                if let previous, previous != result.count { animate(increased: result.count > previous) }
            } catch {
                guard !Task.isCancelled, generation == currentGeneration else { return }
                failed = true
                lastAttemptFailed = true
                // Keep the last successful value. No alert, zero, or false change animation.
            }
            refreshing = false
            let delay = PollPolicy.delay(interval: interval, failed: failed)
            nextCheck = Date().addingTimeInterval(delay)
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
    func save(channel: String, apiKey: String, seconds: Double) throws {
        try Keychain.save(apiKey)
        generation += 1
        request?.cancel(); timer?.invalidate(); flash?.cancel(); refreshing = false
        if channelID != channel { snapshot = nil; UserDefaults.standard.removeObject(forKey: "snapshot") }
        channelID = channel; key = apiKey; interval = seconds
        UserDefaults.standard.set(channel, forKey: "channelID")
        UserDefaults.standard.set(seconds, forKey: "interval")
        render(); refresh()
    }
    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "YT Subs Settings"
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView(model: self, channel: channelID, apiKey: key, amount: String(interval / 60)))
        settingsWindow?.center(); settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func closeSettings() { settingsWindow?.close() }
}

struct Dashboard: View {
    @ObservedObject var model: AppDelegate
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "play.rectangle.fill").foregroundStyle(.red)
                Text("YT Subs").font(.headline)
                Spacer()
                if model.refreshing { ProgressView().controlSize(.small) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.snapshot?.title ?? "Connect your channel").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                Text(model.snapshot.map { SubscriberFormat.string($0.count) } ?? "—").font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("subscribers").foregroundStyle(.secondary)
            }
            if let snapshot = model.snapshot {
                Text("Updated \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                if snapshot.count >= 1000 { Text("YouTube rounds counts to three significant figures.").font(.caption).foregroundStyle(.secondary) }
            }
            if model.lastAttemptFailed {
                Text("Last check skipped. Retrying automatically.").font(.caption).foregroundStyle(.secondary)
            }
            if let next = model.nextCheck { Text("Next check: \(next.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }.disabled(model.refreshing || model.channelID.isEmpty)
                Button("Settings…") { model.showSettings() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }.padding(20).frame(width: 340)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppDelegate
    @State var channel: String
    @State var apiKey: String
    @State var amount: String
    @State private var hours = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Your channel, at a glance", systemImage: "play.rectangle.fill").font(.title2.bold())
            Text("Keep your YouTube subscriber count in the menu bar.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Channel ID or channel URL").font(.headline)
                TextField("UC… or https://www.youtube.com/channel/…", text: $channel)
                Text("Use a /channel/ URL, not an @handle.").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("YouTube Data API key").font(.headline)
                SecureField("Paste your API key", text: $apiKey)
                HStack {
                    Text("Saved securely in macOS Keychain.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Link("Get a free key ↗", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                }
            }
            HStack {
                Text("Check every")
                TextField("1", text: $amount).frame(width: 65)
                Picker("Unit", selection: $hours) { Text("minutes").tag(false); Text("hours").tag(true) }.labelsHidden().frame(width: 115)
            }
            Text("Below 10,000: 1,526 · 10,000+: 10.1k. YouTube may round counts from 1,000 subscribers.").font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { model.closeSettings() }.keyboardShortcut(.cancelAction)
                Button("Save & Connect") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 480)
    }
    func save() {
        guard let id = ChannelInput.id(from: channel) else { message = "Enter a valid channel ID or /channel/ URL."; return }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { message = "Enter your YouTube Data API key."; return }
        guard let value = Double(amount), value.isFinite, value > 0 else { message = "Enter a positive interval."; return }
        let seconds = value * (hours ? 3600 : 60)
        guard seconds >= 60, seconds <= 365 * 86400 else { message = "Choose an interval from 1 minute to 365 days."; return }
        do { try model.save(channel: id, apiKey: key, seconds: seconds); model.closeSettings() }
        catch { message = "Could not save the key in Keychain. Please try again." }
    }
}
