import AppKit
import SwiftUI
import ServiceManagement
import YTSubsCore

@main
struct YTSubsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var launchAtLogin = false
    @Published var loginMessage: String?
    @Published var snapshot: ChannelSnapshot?
    @Published var avatar: NSImage?
    private let avatars = AvatarCache()
    private var avatarTask: Task<Void, Never>?
    @Published var lastAttemptFailed = false
    @Published var errorMessage: String?
    @Published var lastAttempt: Date?
    var source = UserDefaults.standard.string(forKey: "source") ?? "studio"
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
    private var dashboardWindow: NSWindow?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updateLoginStatus()
        if CommandLine.arguments.contains("--enable-login") { setLaunchAtLogin(true) }
        if source == "api" { key = Keychain.read() }
        if let data = UserDefaults.standard.data(forKey: "snapshot"),
           let cached = try? JSONDecoder().decode(ChannelSnapshot.self, from: data), cached.id == channelID,
           Date().timeIntervalSince(cached.fetchedAt) < 30 * 86400 { snapshot = cached }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: Dashboard(model: self))
        avatar = avatars.cached(channelID)
        render()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        if channelID.isEmpty || (source == "api" && key.isEmpty) { showSettings() } else { refresh() }
        if CommandLine.arguments.contains("--settings") { showSettings() }
        if CommandLine.arguments.contains("--show") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                togglePopover()
            }
        }
        if CommandLine.arguments.contains("--dashboard") { showDashboardWindow() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePopover() }; return true
    }
    @objc func woke() { if nextCheck == nil || nextCheck! <= Date() { refresh() } }
    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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
        guard !refreshing, !channelID.isEmpty, (source == "studio" || !key.isEmpty) else { return }
        timer?.invalidate(); nextCheck = nil
        refreshing = true
        let currentGeneration = generation
        let channel = channelID, apiKey = key, selectedSource = source
        request = Task { @MainActor in
            var failed = false
            do {
                let result = try await selectedSource == "studio"
                    ? StudioClient.fetch(channelID: channel)
                    : YouTubeAPI.fetch(channelID: channel, key: apiKey)
                guard !Task.isCancelled, generation == currentGeneration else { return }
                let previous = snapshot?.source == result.source ? snapshot?.count : nil
                snapshot = result
                avatarTask?.cancel()
                avatarTask = Task { @MainActor in
                    let image = await avatars.update(channelID: result.id, url: result.avatarURL)
                    guard !Task.isCancelled, channelID == result.id else { return }
                    avatar = image
                }
                lastAttemptFailed = false
                errorMessage = nil
                if let data = try? JSONEncoder().encode(result) { UserDefaults.standard.set(data, forKey: "snapshot") }
                render()
                if let previous, previous != result.count { animate(increased: result.count > previous) }
            } catch {
                guard !Task.isCancelled, generation == currentGeneration else { return }
                failed = true
                lastAttemptFailed = true
                errorMessage = selectedSource == "studio" ? error.localizedDescription : APIError.response.localizedDescription
                // Keep the last successful value. No alert, zero, or false change animation.
            }
            lastAttempt = Date()
            refreshing = false
            let delay = PollPolicy.delay(interval: interval, failed: failed)
            nextCheck = Date().addingTimeInterval(delay)
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
    func save(channel: String, apiKey: String, seconds: Double, source: String) throws {
        if !apiKey.isEmpty { try Keychain.save(apiKey) }
        generation += 1
        request?.cancel(); timer?.invalidate(); flash?.cancel(); refreshing = false
        if channelID != channel { avatarTask?.cancel(); avatar = nil; snapshot = nil; UserDefaults.standard.removeObject(forKey: "snapshot") }
        channelID = channel; key = apiKey; interval = seconds; self.source = source
        errorMessage = nil; lastAttemptFailed = false
        UserDefaults.standard.set(source, forKey: "source")
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
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView(model: self, channel: channelID, apiKey: key, amount: String(interval / 60), source: source))
        settingsWindow?.center(); settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showDashboardWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "YT Subs"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Dashboard(model: self))
        dashboardWindow = window
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func updateLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        UserDefaults.standard.set(status.rawValue, forKey: "loginItemStatus")
        if status == .requiresApproval {
            loginMessage = "Allow YT Subs in System Settings → General → Login Items."
        }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        loginMessage = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            updateLoginStatus()
        } catch {
            updateLoginStatus()
            loginMessage = "Could not change launch at login: " + error.localizedDescription
        }
    }
    func closeSettings() { settingsWindow?.close() }
}

struct Dashboard: View {
    @ObservedObject var model: AppDelegate
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Group {
                    if let avatar = model.avatar { Image(nsImage: avatar).resizable().scaledToFill() }
                    else { ZStack { Color.red.opacity(0.10); Image(systemName: "play.rectangle.fill").font(.title).foregroundStyle(.red) } }
                }.frame(width: 60, height: 60).clipShape(Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.snapshot?.title ?? "Your YouTube channel").font(.system(size: 20, weight: .semibold)).lineLimit(2)
                    HStack(spacing: 4) {
                        if (model.snapshot?.source ?? model.source) == "studio",
                           let channel = ChannelInput.id(from: model.channelID),
                           let url = URL(string: "https://studio.youtube.com/channel/" + channel) {
                            Link("YouTube Studio", destination: url)
                                .help("Open this channel in YouTube Studio using your default browser")
                            Text("· Exact count").foregroundStyle(.secondary)
                        } else {
                            Text("YouTube API · Rounded count").foregroundStyle(.secondary)
                        }
                    }.font(.system(size: 13))
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.snapshot?.count.formatted(.number.locale(Locale(identifier: "en_US"))) ?? "—")
                    .font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1).fixedSize(horizontal: false, vertical: true)
                Text("Subscribers").font(.system(size: 17)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Last updated", systemImage: "clock")
                    Spacer()
                    Text(model.snapshot?.fetchedAt.formatted(date: .omitted, time: .standard) ?? "Not yet").monospacedDigit()
                }
                if let snapshot = model.snapshot {
                    Text(snapshot.fetchedAt.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                }
                HStack {
                    Label(model.refreshing ? (model.source == "studio" ? "Checking Studio…" : "Checking YouTube…") : "Next check", systemImage: "arrow.clockwise")
                    Spacer()
                    if model.refreshing { ProgressView().controlSize(.small) }
                    else { Text(model.nextCheck?.formatted(date: .omitted, time: .standard) ?? "—").monospacedDigit() }
                }
            }.font(.system(size: 14)).padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            if let error = model.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Update failed", systemImage: "exclamationmark.triangle.fill").font(.system(size: 15, weight: .semibold))
                    Text(error).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                    if let attempt = model.lastAttempt { Text("Failed at " + attempt.formatted(date: .omitted, time: .standard) + ". Keeping the last successful count.").font(.system(size: 13)) }
                }.foregroundStyle(.red).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 12) {
                Button { model.refresh() } label: { Label(model.refreshing ? "Updating…" : "Update now", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).disabled(model.refreshing || model.channelID.isEmpty)
                    .help("Fetch the latest subscriber count immediately")
                Button("Settings…") { model.showSettings() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.foregroundStyle(.secondary)
            }.controlSize(.large)
        }.padding(24).frame(width: 410).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppDelegate
    @State var channel: String
    @State var apiKey: String
    @State var amount: String
    @State var source: String
    @State private var hours = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Your channel, at a glance", systemImage: "play.rectangle.fill").font(.title2.bold())
            Text("Keep your YouTube subscriber count in the menu bar.").foregroundStyle(.secondary)
            Picker("Get subscriber count from", selection: $source) {
                Text("YouTube Studio (exact)").tag("studio")
                Text("YouTube API (rounded)").tag("api")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Channel ID or channel URL").font(.headline)
                TextField("UC… or https://www.youtube.com/channel/…", text: $channel)
                Text("Use a /channel/ URL, not an @handle.").font(.caption).foregroundStyle(.secondary)
            }
            if source == "studio" {
                Text("Enable YT Subs Studio in Chrome. Each check briefly opens an inactive Studio tab using your existing sign-in, then closes it.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("YouTube Data API key").font(.headline)
                SecureField("Paste a key, or leave blank to reuse the saved key", text: $apiKey)
                HStack {
                    Text("Saved securely in macOS Keychain.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Link("Get a free key ↗", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                }
            }
            }
            HStack {
                Text("Check every")
                TextField("1", text: $amount).frame(width: 65)
                Picker("Unit", selection: $hours) { Text("minutes").tag(false); Text("hours").tag(true) }.labelsHidden().frame(width: 115)
            }
            Toggle("Launch YT Subs at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            if let loginMessage = model.loginMessage {
                Text(loginMessage).font(.system(size: 13)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text(source == "studio" ? "Menu bar: 1,526 below 10,000; 10.1k above. Studio provides the exact count at each check." : "YouTube API rounds counts from 1,000 subscribers. Choose Studio for exact counts.").font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
        var key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if source == "api" && key.isEmpty { key = Keychain.read() }
        guard source == "studio" || !key.isEmpty else { message = "Enter your YouTube Data API key."; return }
        guard let value = Double(amount), value.isFinite, value > 0 else { message = "Enter a positive interval."; return }
        let seconds = value * (hours ? 3600 : 60)
        guard seconds >= 60, seconds <= 365 * 86400 else { message = "Choose an interval from 1 minute to 365 days."; return }
        do { try model.save(channel: id, apiKey: key, seconds: seconds, source: source); model.closeSettings() }
        catch { message = "Could not save the key in Keychain. Please try again." }
    }
}
