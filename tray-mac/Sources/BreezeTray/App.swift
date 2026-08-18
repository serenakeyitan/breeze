import SwiftUI
import AppKit
@preconcurrency import UserNotifications
import BreezeTrayCore

let daemonHTTPPort: Int = {
    let yaml = try? String(contentsOf: BreezePaths.configFile(), encoding: .utf8)
    var plistPort: Int?
    if let plistURL = DaemonPlistParser.findPlist(in: BreezePaths.launchdDirectory()),
       let data = try? Data(contentsOf: plistURL),
       let config = DaemonPlistParser.parsePlistData(data) {
        plistPort = config.httpPort
    }
    return DaemonPort.resolve(yaml: yaml, plistHTTPPort: plistPort)
}()

let daemonBaseURL = DaemonPort.baseURL(port: daemonHTTPPort)

@MainActor
func postUserNotification(title: String, body: String) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert]) { granted, _ in
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(req)
    }
}

struct InboxItem: Identifiable, Hashable {
    let id: String
    let number: Int
    let type: String
    let repo: String
    let title: String
    let htmlURL: URL

    var repoShort: String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }

    var symbolName: String {
        switch type {
        case "PullRequest": return "arrow.triangle.pull"
        case "Issue": return "smallcircle.filled.circle"
        case "Discussion": return "bubble.left"
        default: return "bell"
        }
    }
}

enum DaemonState {
    case loading, offline, paused, idle, working
}

@MainActor
final class InboxModel: ObservableObject {
    @Published var allItems: [InboxItem] = []
    @Published var seen: Set<String> = []
    @Published var state: DaemonState = .loading
    @Published var lastError: String?

    private var timer: Timer?
    private let endpoint = URL(string: "\(daemonBaseURL)/inbox")!
    private let pollInterval: TimeInterval = 5
    private let offlineThreshold = 3
    private var consecutiveFailures = 0
    private(set) var pausedByUser = false
    private var pausedAt: Date?
    private var notifiedDriftWhilePaused = false
    private let seenFile = BreezePaths.traySeenFile()

    init() { seen = loadSeen() }

    var unseenItems: [InboxItem] { allItems.filter { !seen.contains($0.id) } }
    var unseenCount: Int { unseenItems.count }

    func start() {
        Task { await refresh() }
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.consecutiveFailures = 0
                await self?.refresh()
            }
        }
    }

    private func loadSeen() -> Set<String> {
        guard let data = try? Data(contentsOf: seenFile),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    private func saveSeen() {
        try? FileManager.default.createDirectory(at: seenFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Array(seen).sorted()) {
            try? data.write(to: seenFile, options: .atomic)
        }
    }

    func markSeen(_ id: String) {
        seen.insert(id)
        saveSeen()
        recomputeState()
    }

    func markPaused(_ paused: Bool) {
        pausedByUser = paused
        if paused {
            state = .paused
            pausedAt = Date()
            notifiedDriftWhilePaused = false
        } else {
            state = .loading
            pausedAt = nil
            notifiedDriftWhilePaused = false
            Task { await refresh() }
        }
    }

    func refresh() async {
        if pausedByUser {
            let recentlyPaused = pausedAt.map { Date().timeIntervalSince($0) < 30 } ?? false
            if !recentlyPaused, !notifiedDriftWhilePaused {
                var req = URLRequest(url: endpoint)
                req.timeoutInterval = 2
                if let (_, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse,
                   http.statusCode == 200 {
                    notifiedDriftWhilePaused = true
                    postUserNotification(
                        title: "Daemon is still running",
                        body: "breeze is alive even though the menu bar shows Paused. Click Resume, or run `breeze-runner stop`."
                    )
                }
            }
            return
        }
        do {
            var req = URLRequest(url: endpoint)
            req.timeoutInterval = 4
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                handleFailure("HTTP \(((resp as? HTTPURLResponse)?.statusCode).map(String.init) ?? "?")")
                return
            }
            let snapshot = try InboxParser.parse(data: data)
            let items: [InboxItem] = snapshot.humanItems.compactMap { n in
                guard let url = URL(string: n.htmlURL) else { return nil }
                return InboxItem(
                    id: n.id, number: n.number, type: n.type,
                    repo: n.repo, title: n.title, htmlURL: url
                )
            }
            let liveIDs = Set(items.map(\.id))
            let newSeen = seen.intersection(liveIDs)
            if newSeen != seen {
                seen = newSeen
                saveSeen()
            }
            allItems = items
            consecutiveFailures = 0
            lastError = nil
            recomputeState()
        } catch {
            handleFailure(error.localizedDescription)
        }
    }

    private func handleFailure(_ msg: String) {
        consecutiveFailures += 1
        lastError = msg
        if consecutiveFailures >= offlineThreshold {
            state = .offline
            allItems = []
        }
    }

    private func recomputeState() {
        if pausedByUser { state = .paused; return }
        state = unseenCount > 0 ? .working : .idle
    }
}

struct DaemonOperation {
    enum Phase { case starting, stopping }
    let phase: Phase
    let startedAt: Date
}

@MainActor
final class DaemonController: ObservableObject {
    @Published var isWorking = false
    @Published var operation: DaemonOperation?
    @Published var elapsedSeconds = 0

    private var elapsedTimer: Timer?
    private let stateFile = BreezePaths.trayStateFile()

    func startResumeInBackground(inbox: InboxModel) {
        beginOperation(.starting)
        Task {
            defer { endOperation() }
            do {
                try await resumeDaemon()
                inbox.markPaused(false)
                await inbox.refresh()
            } catch {
                WindowManager.shared.showError(
                    title: "Could not resume daemon",
                    message: "Check that breeze-runner is installed and a repo scope was saved. You can also run `breeze-runner start --allow-repo owner/repo`.",
                    error: error
                )
            }
        }
    }

    func startPauseInBackground(inbox: InboxModel) {
        beginOperation(.stopping)
        Task {
            defer { endOperation() }
            do {
                try await pauseDaemon()
                inbox.markPaused(true)
            } catch {
                WindowManager.shared.showError(
                    title: "Could not pause daemon",
                    message: "Verify with `breeze-runner status`.",
                    error: error
                )
            }
        }
    }

    private func beginOperation(_ phase: DaemonOperation.Phase) {
        operation = DaemonOperation(phase: phase, startedAt: Date())
        elapsedSeconds = 0
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let op = self.operation else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(op.startedAt))
            }
        }
        if let t = elapsedTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func endOperation() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        operation = nil
        elapsedSeconds = 0
    }

    @discardableResult
    func runCLI(_ args: [String]) async throws -> String {
        isWorking = true
        defer { isWorking = false }
        let process = Process()
        let pipe = Pipe()
        let argv = Self.breezeInvocation(args: args)
        process.executableURL = URL(fileURLWithPath: argv.executable)
        process.arguments = argv.arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.runtimePath
        process.environment = env
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "DaemonController",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func breezeInvocation(args: [String]) -> (executable: String, arguments: [String]) {
        if let fromPlist = readPlist()?.executable,
           FileManager.default.isExecutableFile(atPath: fromPlist) {
            return (executable: fromPlist, arguments: args)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.breeze/bin/breeze-runner",
            "\(home)/.local/bin/breeze-runner",
            "/usr/local/bin/breeze-runner",
            "/opt/homebrew/bin/breeze-runner",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return (executable: path, arguments: args)
        }
        return (executable: "/usr/bin/env", arguments: ["breeze-runner"] + args)
    }

    private static let runtimePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin",
            "\(home)/.breeze/bin",
            "\(home)/.nvm/versions/node/v22.22.1/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ].joined(separator: ":")
    }()

    func pauseDaemon() async throws {
        if let snapshot = Self.readPlist() {
            saveState(
                allowedRepos: snapshot.allowedRepos,
                httpPort: snapshot.httpPort,
                authorFollowRepos: snapshot.authorFollowRepos
            )
        } else if let repos = try? await fetchAllowedRepos(), !repos.isEmpty {
            saveState(allowedRepos: repos, httpPort: nil, authorFollowRepos: [])
        }
        try await runCLI(DaemonCommand.stopArguments)
    }

    func resumeDaemon() async throws {
        let state: PersistedState
        if let recovered = Self.readPlist(), !recovered.allowedRepos.isEmpty {
            saveState(
                allowedRepos: recovered.allowedRepos,
                httpPort: recovered.httpPort,
                authorFollowRepos: recovered.authorFollowRepos
            )
            guard let reloaded = loadState() else {
                throw NSError(domain: "DaemonController", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Recovered repo scope from launchd plist but failed to persist it."
                ])
            }
            state = reloaded
        } else if let saved = loadState(), !saved.allowedRepos.isEmpty {
            state = saved
        } else {
            throw NSError(domain: "DaemonController", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No saved repo scope. Run `breeze-runner start --allow-repo owner/repo` once."
            ])
        }
        try await runCLI(DaemonCommand.startArguments(
            allowedRepos: state.allowedRepos,
            httpPort: state.httpPort,
            authorFollowRepos: state.authorFollowRepos ?? []
        ))
        let healthy = await waitForDaemonHealth(timeoutSec: 20)
        if !healthy {
            throw NSError(domain: "DaemonController", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "start returned success, but breeze did not come up within 20 seconds."
            ])
        }
    }

    private func waitForDaemonHealth(timeoutSec: Int) async -> Bool {
        let url = URL(string: "\(daemonBaseURL)/healthz") ?? URL(string: "\(daemonBaseURL)/inbox")!
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSec))
        while Date() < deadline {
            var req = URLRequest(url: url)
            req.timeoutInterval = 1.5
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               http.statusCode == 200 {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    func stop() async throws {
        try await runCLI(DaemonCommand.stopArguments)
    }

    private func fetchAllowedRepos() async throws -> [String] {
        DaemonCommand.parseAllowedRepos(fromStatus: try await runCLI(DaemonCommand.statusArguments))
    }

    private static func readPlist() -> DaemonPlistConfig? {
        guard let url = DaemonPlistParser.findPlist(in: BreezePaths.launchdDirectory()),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return DaemonPlistParser.parsePlistData(data)
    }

    private struct PersistedState: Codable {
        let allowedRepos: [String]
        let httpPort: Int?
        let authorFollowRepos: [String]?
        let savedAt: Date
    }

    private func saveState(allowedRepos: [String], httpPort: Int?, authorFollowRepos: [String] = []) {
        try? FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = PersistedState(
            allowedRepos: allowedRepos,
            httpPort: httpPort,
            authorFollowRepos: authorFollowRepos,
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: stateFile, options: .atomic)
        }
    }

    private func loadState() -> PersistedState? {
        guard let data = try? Data(contentsOf: stateFile) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }
}

@main
struct BreezeTrayApp: App {
    @StateObject private var inbox = InboxModel()
    @StateObject private var daemon = DaemonController()

    var body: some Scene {
        MenuBarExtra {
            DropdownView()
                .environmentObject(inbox)
                .environmentObject(daemon)
        } label: {
            TrayLabel()
                .environmentObject(inbox)
        }
        .menuBarExtraStyle(.window)
    }
}

struct TrayLabel: View {
    @EnvironmentObject var inbox: InboxModel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "wind")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .opacity(iconOpacity)
            if inbox.unseenCount > 0 {
                Text("\(inbox.unseenCount)")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .onAppear { inbox.start() }
    }

    private var iconOpacity: Double {
        switch inbox.state {
        case .loading: return 0.5
        case .offline: return 0.4
        case .paused: return 0.5
        case .idle: return 0.7
        case .working: return 1.0
        }
    }
}

struct DropdownView: View {
    @EnvironmentObject var inbox: InboxModel
    @EnvironmentObject var daemon: DaemonController
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusRow()
            Divider().padding(.horizontal, 4).padding(.vertical, 2)
            content
            Divider().padding(.horizontal, 4).padding(.vertical, 2)
            FooterButton(title: "Open dashboard", systemImage: "rectangle.on.rectangle") {
                openURL(URL(string: "\(daemonBaseURL)/")!)
            }
            FooterButton(title: "Preferences…", systemImage: "gearshape") {
                WindowManager.shared.openPreferences(daemon: daemon)
            }
            FooterButton(title: "Quit", systemImage: "power") {
                WindowManager.shared.openQuitConfirm(inbox: inbox, daemon: daemon)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .frame(minWidth: 200, idealWidth: 200, maxWidth: 260)
    }

    @ViewBuilder
    private var content: some View {
        switch inbox.state {
        case .loading:
            statusLine(systemImage: "ellipsis.circle", text: "Loading…")
        case .offline:
            statusLine(systemImage: "exclamationmark.triangle", text: "Daemon offline")
        case .paused, .idle:
            if inbox.allItems.isEmpty {
                statusLine(systemImage: "checkmark.circle", text: "All clear")
            } else {
                itemsList
            }
        case .working:
            itemsList
        }
    }

    private var itemsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(inbox.allItems) { item in
                InboxRow(item: item, seen: inbox.seen.contains(item.id))
                    .onTapGesture {
                        inbox.markSeen(item.id)
                        openURL(item.htmlURL)
                    }
            }
        }
    }

    private func statusLine(systemImage: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).frame(width: 16)
            Text(text).font(.system(size: 13))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
    }
}

struct StatusRow: View {
    @EnvironmentObject var inbox: InboxModel
    @EnvironmentObject var daemon: DaemonController

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            Text(label).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 12)
            actionButton
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }

    private var dotColor: Color {
        switch inbox.state {
        case .loading: return .gray
        case .offline: return .red
        case .paused: return .yellow
        case .idle, .working: return .green
        }
    }

    private var label: String {
        switch inbox.state {
        case .loading: return "Starting…"
        case .offline: return "Offline"
        case .paused: return "Paused"
        case .idle, .working: return "Online"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let op = daemon.operation {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
                Text(op.phase == .starting ? "Starting… \(daemon.elapsedSeconds)s" : "Stopping…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        } else {
            switch inbox.state {
            case .loading:
                EmptyView()
            case .offline, .paused:
                ControlButton(label: inbox.state == .paused ? "Resume" : "Start", systemImage: "play.fill") {
                    daemon.startResumeInBackground(inbox: inbox)
                }
            case .idle, .working:
                ControlButton(label: "Pause", systemImage: "pause.fill") {
                    daemon.startPauseInBackground(inbox: inbox)
                }
            }
        }
    }
}

struct ControlButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            Text(label).font(.system(size: 11, weight: .medium))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 4).fill(hover ? Color.primary.opacity(0.16) : Color.primary.opacity(0.08)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
    }
}

struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).frame(width: 16)
            Text(title).font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(hover ? Color.primary.opacity(0.08) : .clear)
        .cornerRadius(4)
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
    }
}

struct InboxRow: View {
    let item: InboxItem
    let seen: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbolName).frame(width: 16, height: 16)
            Text("\(item.repoShort) · #\(item.number)").font(.system(size: 13)).strikethrough(seen, color: .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(seen ? 0.45 : 1.0)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(hover ? Color.primary.opacity(0.08) : .clear)
        .cornerRadius(4)
        .onHover { hover = $0 }
    }
}

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var preferencesWindow: NSWindow?
    private var quitConfirmWindow: NSWindow?

    func openPreferences(daemon: DaemonController) {
        if let w = preferencesWindow {
            centerOnMainScreen(w)
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: PreferencesView(daemon: daemon, onClose: { [weak self] in
            self?.preferencesWindow?.close()
        }))
        let w = NSWindow(contentViewController: host)
        w.title = "breeze preferences"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 460, height: 320))
        centerOnMainScreen(w)
        w.delegate = WindowCloseObserver.shared
        preferencesWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openQuitConfirm(inbox: InboxModel, daemon: DaemonController) {
        if let w = quitConfirmWindow {
            centerOnMainScreen(w)
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = QuitConfirmView(
            onPauseInstead: { [weak self] in
                daemon.startPauseInBackground(inbox: inbox)
                self?.quitConfirmWindow?.close()
            },
            onCancel: { [weak self] in self?.quitConfirmWindow?.close() },
            onQuit: { [weak self] in
                Task {
                    do {
                        try await daemon.stop()
                        NSApp.terminate(nil)
                    } catch {
                        self?.quitConfirmWindow?.close()
                        WindowManager.shared.showQuitFailed(error: error)
                    }
                }
            }
        )
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Quit breeze?"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 420, height: 220))
        centerOnMainScreen(w)
        w.delegate = WindowCloseObserver.shared
        quitConfirmWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func centerOnMainScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }

    func didClose(_ window: NSWindow) {
        if window === preferencesWindow { preferencesWindow = nil }
        if window === quitConfirmWindow { quitConfirmWindow = nil }
    }

    func showError(title: String, message: String, error: Error? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message + (error.map { "\n\n\($0.localizedDescription)" } ?? "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func showQuitFailed(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not stop daemon"
        alert.informativeText = "breeze-runner is still running. Stay open and retry, or force quit (daemon stays in the background until `breeze-runner stop`).\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stay open")
        alert.addButton(withTitle: "Force quit anyway")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }
}

final class WindowCloseObserver: NSObject, NSWindowDelegate {
    static let shared = WindowCloseObserver()
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in WindowManager.shared.didClose(window) }
    }
}

struct QuitConfirmView: View {
    let onPauseInstead: () -> Void
    let onCancel: () -> Void
    let onQuit: () -> Void
    @State private var copied = false
    private let restartCommand = "breeze-runner start --allow-repo owner/repo"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quit breeze?").font(.system(size: 15, weight: .semibold))
            Text("This stops the daemon. To resume PR auto review, run this or relaunch the tray:")
                .font(.system(size: 12))
            HStack {
                Text(restartCommand)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(6)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(restartCommand, forType: .string)
                    copied = true
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Quit", role: .destructive, action: onQuit)
                Button("Pause Instead", action: onPauseInstead).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct PreferencesView: View {
    let daemon: DaemonController
    let onClose: () -> Void
    @State private var copiedScope = false
    @State private var latestVersion: String?
    @State private var checkingUpdates = false

    private let currentVersion: String = {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "dev"
    }()

    private let scopePrompt = "Change the breeze repo scope. Current allow-list: <run breeze-runner status>. Update to: <owner/repo>. Restart the daemon and confirm the new scope."

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Preferences").font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("Repo scope").font(.system(size: 13, weight: .semibold))
                Text("Which repos breeze reviews. Copy this prompt into your coding agent.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button(copiedScope ? "Copied" : "Copy prompt") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(scopePrompt, forType: .string)
                    copiedScope = true
                }
                .buttonStyle(.borderless)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Version").font(.system(size: 13, weight: .semibold))
                HStack {
                    Text("v\(currentVersion)").font(.system(size: 12, design: .monospaced))
                    Spacer()
                    if checkingUpdates {
                        ProgressView().scaleEffect(0.6)
                    } else if let latest = latestVersion {
                        Text(latest == currentVersion ? "Up to date" : "v\(latest) available")
                            .font(.system(size: 11))
                            .foregroundStyle(latest == currentVersion ? .green : .orange)
                    } else {
                        Button("Check for updates") { Task { await checkUpdates() } }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Close", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { Task { await checkUpdates() } }
    }

    private func checkUpdates() async {
        checkingUpdates = true
        defer { checkingUpdates = false }
        guard let url = URL(string: "https://api.github.com/repos/serenakeyitan/breeze/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tag = obj["tag_name"] as? String {
            latestVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        }
    }
}
