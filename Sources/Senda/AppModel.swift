import AppKit
import SwiftUI
import SFTPCore

@MainActor
final class AppModel: ObservableObject {
    @Published var hosts: [SSHHost] = []
    let demoMode: Bool
    @Published var hostInput = ""
    @Published var connectedHost = ""
    @Published var isConnecting = false
    @Published var localPath = ""
    @Published var remotePath = ""
    @Published private(set) var localAddressFile: FileEntry?
    @Published private(set) var remoteAddressFile: FileEntry?
    @Published private(set) var localNavigationRevision = UUID()
    @Published private(set) var remoteNavigationRevision = UUID()
    var localAddress: String { localAddressFile?.path ?? localPath }
    var remoteAddress: String { remoteAddressFile?.path ?? remotePath }
    var localFiles: [FileEntry] = [] { didSet { visibleLocal = filter(localFiles, addressed: localAddressFile) } }
    var remoteFiles: [FileEntry] = [] { didSet { visibleRemote = filter(remoteFiles, addressed: remoteAddressFile) } }
    @Published private(set) var visibleLocal: [FileEntry] = []
    @Published private(set) var visibleRemote: [FileEntry] = []
    @Published var localSelection = Set<String>()
    @Published var remoteSelection = Set<String>()
    @Published var isRemoteLoading = false
    @Published var isLocalLoading = false
    @Published var showHidden = false {
        didSet {
            preferences.set(showHidden, forKey: "showHidden")
            visibleLocal = filter(localFiles, addressed: localAddressFile)
            visibleRemote = filter(remoteFiles, addressed: remoteAddressFile)
            localSelection.formIntersection(Set(visibleLocal.map(\.path)))
            remoteSelection.formIntersection(Set(visibleRemote.map(\.path)))
        }
    }
    @Published var jobs: [TransferJob] = [] {
        didSet {
            let count = jobs.reduce(0) { $0 + (($1.state == .waiting || $1.state == .running) ? 1 : 0) }
            if activeJobs != count { activeJobs = count }
        }
    }
    @Published private(set) var activeJobs = 0
    @Published var alertMessage: String?
    @Published var status = "选择一台开发机，开始连接"
    @Published var proxyPath = "" { didSet { preferences.set(proxyPath, forKey: "proxyPath") } }
    private let preferences: UserDefaults
    private let sessionFactory: (String, String, String?) throws -> SFTPSession
    private var browser: SFTPSession?
    private var connectionID = UUID()
    private var listingID = UUID()
    private var localListingID = UUID()
    private var runningQueue = false
    private(set) var transferConnectionsOpened = 0
    private var browseCancellation: Cancellation?
    private var transferRefresh: Task<Void, Never>?
    private var dirtyLocalDirectories = Set<String>()
    private var dirtyRemoteDirectories: [String: Set<String>] = [:]

    var connected: Bool { (demoMode || browser != nil) && !connectedHost.isEmpty }

    init(preferences: UserDefaults = .standard, loadFiles: Bool = true, loadHosts: Bool = true, demoMode: Bool = false,
         sessionFactory: @escaping (String, String, String?) throws -> SFTPSession = { try SFTPSession(host: $0, proxyPath: $1, askpass: $2) }) {
        self.demoMode = demoMode
        self.sessionFactory = sessionFactory
        hosts = demoMode || !loadHosts ? [] : SSHConfig.hosts()
        self.preferences = preferences
        hostInput = preferences.string(forKey: "lastHost") ?? hosts.first?.alias ?? ""
        localPath = preferences.string(forKey: "localPath") ?? FileManager.default.homeDirectoryForCurrentUser.path
        showHidden = preferences.bool(forKey: "showHidden")
        proxyPath = preferences.string(forKey: "proxyPath") ?? ""
        if loadFiles { refreshLocal() }
    }

    func selectedEntries(remote: Bool) -> [FileEntry] {
        let selection = remote ? remoteSelection : localSelection
        return (remote ? visibleRemote : visibleLocal).filter { selection.contains($0.path) }
    }

    func selectAll(remote: Bool) {
        let paths = Set((remote ? visibleRemote : visibleLocal).map(\.path))
        if remote { remoteSelection = paths } else { localSelection = paths }
    }

    func deselectAll(remote: Bool) {
        if remote { remoteSelection = [] } else { localSelection = [] }
    }

    private func filter(_ entries: [FileEntry], addressed: FileEntry?) -> [FileEntry] {
        showHidden || addressed != nil ? entries : entries.filter { !$0.name.hasPrefix(".") }
    }

    func refreshHosts() { if !demoMode { hosts = SSHConfig.hosts() } }

    func refreshLocal() { navigateLocal(localAddress) }

    func navigateLocal(_ requested: String) {
        guard !demoMode else { return }
        let directory = localPath, token = UUID()
        localListingID = token; isLocalLoading = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try BrowserLocation.local(requested, relativeTo: directory)
                }.value
                guard localListingID == token else { return }
                showLocation(result, remote: false); isLocalLoading = false
            } catch {
                guard localListingID == token else { return }
                isLocalLoading = false; alertMessage = "无法打开本地路径：\(error.localizedDescription)"
            }
        }
    }

    func showLocation(_ location: BrowserLocation, remote: Bool) {
        if remote {
            let sameDirectory = remotePath == location.directoryPath
            remotePath = location.directoryPath; remoteAddressFile = location.file; remoteFiles = location.entries
            if let file = location.file { remoteSelection = [file.path] }
            else if sameDirectory { remoteSelection.formIntersection(Set(visibleRemote.map(\.path))) }
            else { remoteSelection = [] }
            preferences.set(remotePath, forKey: "remotePath.\(connectedHost)")
            remoteNavigationRevision = UUID()
        } else {
            let sameDirectory = localPath == location.directoryPath
            localPath = location.directoryPath; localAddressFile = location.file; localFiles = location.entries
            if let file = location.file { localSelection = [file.path] }
            else if sameDirectory { localSelection.formIntersection(Set(visibleLocal.map(\.path))) }
            else { localSelection = [] }
            preferences.set(localPath, forKey: "localPath")
            localNavigationRevision = UUID()
        }
    }

    func chooseLocalFolder() {
        guard !demoMode else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = URL(fileURLWithPath: localPath)
        panel.prompt = "打开目录"
        if panel.runModal() == .OK, let url = panel.url { navigateLocal(url.path) }
    }

    func connect(_ alias: String? = nil) {
        guard !demoMode else { return }
        let host = (alias ?? hostInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        disconnect(); hostInput = host; isConnecting = true
        status = "正在连接 \(host)…"
        let token = connectionID
        Task {
            var session: SFTPSession?
            do {
                let created = try sessionFactory(host, proxyPath, Bundle.main.executablePath)
                session = created; browser = created
                let saved = preferences.string(forKey: "remotePath.\(host)")
                let path = try await created.perform { session in
                    try session.handshake()
                    if let saved, (try? session.stat(saved).isDirectory) == true { return try session.realpath(saved) }
                    return try session.realpath(".")
                }
                guard token == connectionID else { created.stop(); return }
                connectedHost = host; isConnecting = false
                preferences.set(host, forKey: "lastHost")
                status = "已连接 · \(host)"
                navigateRemote(path)
            } catch {
                session?.stop()
                guard token == connectionID else { return }
                browser = nil; isConnecting = false; status = "连接失败"
                alertMessage = "无法连接 \(host)\n\n\(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        connectionID = UUID(); listingID = UUID()
        browseCancellation?.cancel(); browseCancellation = nil
        browser?.stop(); browser = nil
        connectedHost = ""; remotePath = ""; remoteAddressFile = nil; remoteFiles = []; remoteSelection = []
        remoteNavigationRevision = UUID()
        isConnecting = false; isRemoteLoading = false
        status = "连接已断开"
    }

    func navigateRemote(_ requested: String) {
        guard !demoMode else { return }
        guard let session = browser, connected else { return }
        let token = UUID(), directory = remotePath; listingID = token
        browseCancellation?.cancel()
        let cancellation = Cancellation(); browseCancellation = cancellation
        isRemoteLoading = true
        Task {
            do {
                let result = try await session.perform { session in
                    try session.location(at: requested, relativeTo: directory, cancellation: cancellation)
                }
                guard listingID == token else { return }
                showLocation(result, remote: true)
                isRemoteLoading = false
                status = "已连接 · \(connectedHost)"
            } catch {
                guard listingID == token else { return }
                isRemoteLoading = false; alertMessage = "无法打开远程路径\n\n\(error.localizedDescription)"
            }
        }
    }

    func refreshRemote() { navigateRemote(remoteAddress) }

    func canTransferAddressFile(remote: Bool) -> Bool {
        connected && !isLocalLoading && !isRemoteLoading && !localPath.isEmpty && !remotePath.isEmpty &&
        (remote ? remoteAddressFile : localAddressFile)?.isRegularFile == true
    }

    func transferAddressFile(remote: Bool) {
        guard canTransferAddressFile(remote: remote), let file = remote ? remoteAddressFile : localAddressFile else { return }
        if remote { enqueueDownload(file, directory: URL(fileURLWithPath: localPath)) }
        else { upload([URL(fileURLWithPath: file.path)]) }
    }

    func uploadSelection() { upload(selectedEntries(remote: false).map { URL(fileURLWithPath: $0.path) }) }

    func upload(_ urls: [URL], to path: String? = nil) {
        guard connected else { return }
        let target = path ?? remotePath
        appendJobs(urls.filter(\.isFileURL).map { url in
            TransferJob(host: connectedHost, name: url.lastPathComponent, uploading: true, localURL: url, remotePath: RemotePath.join(target, url.lastPathComponent))
        })
    }

    func downloadSelection() {
        guard connected else { return }
        enqueueDownloads(selectedEntries(remote: true).map { ($0, connectedHost) }, directory: URL(fileURLWithPath: localPath))
    }

    func enqueueDownload(_ entry: FileEntry, directory: URL, host: String? = nil) {
        guard (connected || host != nil), RemotePath.safeName(entry.name) else { return }
        enqueueDownloads([(entry, host ?? connectedHost)], directory: directory)
    }

    func enqueueDownloads(_ files: [(entry: FileEntry, host: String)], directory: URL) {
        appendJobs(files.filter { RemotePath.safeName($0.entry.name) }.map { entry, host in
            TransferJob(host: host, name: entry.name, uploading: false, localURL: directory.appendingPathComponent(entry.name), remotePath: entry.path)
        })
    }

    private func appendJobs(_ additions: [TransferJob]) {
        guard !demoMode else { return }
        guard !additions.isEmpty else { return }
        jobs.append(contentsOf: additions)
        startQueue()
    }

    func promisedDownload(_ entry: FileEntry, host: String, destination: URL, completion: @escaping (Error?) -> Void) {
        guard !demoMode else { completion(SFTPError("演示模式不会传输文件")); return }
        let job = TransferJob(host: host, name: entry.name, uploading: false, localURL: destination, remotePath: entry.path)
        job.completion = completion
        appendJobs([job])
    }

    func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs[index]
        guard job.state == .waiting || job.state == .running else { return }
        job.cancellation.cancel(); job.cancellationRequested = true
        if job.state == .waiting {
            finish(job, state: .cancelled, error: SFTPError("传输已取消"))
        }
        // Give the current request window a moment to drain and clean up, then interrupt stalls.
        if job.state == .running {
            Task { @MainActor [weak job] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // A completed job's reused session may now belong to the next transfer.
                guard let job, job.state == .running, job.cancellationRequested else { return }
                job.session?.stop()
            }
        }
    }

    func clearFinished() { jobs.removeAll { $0.state != .waiting && $0.state != .running } }

    private func startQueue() {
        guard !runningQueue else { return }
        runningQueue = true
        Task {
            var reusable: (host: String, proxyPath: String, session: SFTPSession)?
            defer {
                reusable?.session.stop()
                transferRefresh?.cancel(); transferRefresh = nil
                flushTransferRefresh()
                runningQueue = false
            }
            while let index = jobs.firstIndex(where: { $0.state == .waiting }) {
                let job = jobs[index]
                job.state = .running; job.startedAt = Date()
                do {
                    try job.cancellation.check()
                    let created: SFTPSession, needsHandshake: Bool
                    if let existing = reusable, existing.host == job.host, existing.proxyPath == proxyPath {
                        created = existing.session; needsHandshake = false
                    } else {
                        reusable?.session.stop(); reusable = nil
                        created = try sessionFactory(job.host, proxyPath, Bundle.main.executablePath)
                        transferConnectionsOpened += 1
                        reusable = (job.host, proxyPath, created); needsHandshake = true
                    }
                    job.session = created
                    let uploading = job.uploading, localURL = job.localURL, remote = job.remotePath
                    let cancellation = job.cancellation, isPromise = job.completion != nil
                    let result = try await created.perform { session -> (String, UInt64, UInt64) in
                        if needsHandshake { try session.handshake() }
                        var lastUpdate = Date.distantPast
                        var finalCompleted: UInt64 = 0, finalTotal: UInt64 = 0
                        let progress: SFTPSession.Progress = { completed, total in
                            finalCompleted = completed; finalTotal = total
                            guard Date().timeIntervalSince(lastUpdate) > 0.1 || completed == total else { return }
                            lastUpdate = Date()
                            Task { @MainActor [weak job] in
                                guard let job, job.state == .running else { return }
                                if !job.hasProgress { job.hasProgress = true }
                                if job.completed < completed { job.completed = completed }
                                if job.total != total { job.total = total }
                            }
                        }
                        let resolved: (String) -> Void = { path in
                            Task { @MainActor [weak job] in job?.resolvedDestinationPath = path }
                        }
                        if uploading {
                            let path = try session.upload(localURL, to: remote, cancellation: cancellation, progress: progress, destinationResolved: resolved)
                            return (path, finalCompleted, finalTotal)
                        } else {
                            let target = isPromise ? localURL : Self.uniqueLocalURL(localURL)
                            resolved(target.path)
                            try session.download(remote, to: target, cancellation: cancellation, progress: progress)
                            return (target.path, finalCompleted, finalTotal)
                        }
                    }
                    job.resolvedDestinationPath = result.0
                    job.completed = result.1; job.total = result.2; job.hasProgress = true
                    finish(job, state: .done)
                    scheduleTransferRefresh(job)
                } catch {
                    reusable?.session.stop(); reusable = nil
                    finish(job, state: job.cancellation.isCancelled ? .cancelled : .failed, error: error)
                    scheduleTransferRefresh(job)
                }
            }
        }
    }

    private func finish(_ job: TransferJob, state: TransferState, error: Error? = nil) {
        let wasActive = job.state == .waiting || job.state == .running
        job.state = state; job.error = error?.localizedDescription ?? ""; job.session = nil
        if wasActive { activeJobs = max(0, activeJobs - 1) }
        let callback = job.completion; job.completion = nil
        callback?(error)
    }

    private func scheduleTransferRefresh(_ job: TransferJob) {
        if job.uploading { dirtyRemoteDirectories[job.host, default: []].insert(RemotePath.parent(job.remotePath)) }
        else { dirtyLocalDirectories.insert(job.localURL.deletingLastPathComponent().standardizedFileURL.path) }
        guard transferRefresh == nil else { return }
        transferRefresh = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            guard let self else { return }
            self.transferRefresh = nil; self.flushTransferRefresh()
        }
    }

    private func flushTransferRefresh() {
        if dirtyLocalDirectories.contains(URL(fileURLWithPath: localPath).standardizedFileURL.path) { refreshLocal() }
        if connected, dirtyRemoteDirectories[connectedHost]?.contains(remotePath) == true { refreshRemote() }
        dirtyLocalDirectories.removeAll(); dirtyRemoteDirectories.removeAll()
    }

    nonisolated static func uniqueLocalURL(_ requested: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: requested.path) { return requested }
        var isDirectory: ObjCBool = false
        fm.fileExists(atPath: requested.path, isDirectory: &isDirectory)
        let ext = isDirectory.boolValue ? "" : requested.pathExtension
        let stem = ext.isEmpty ? requested.lastPathComponent : requested.deletingPathExtension().lastPathComponent
        for index in 2...10000 {
            let url = requested.deletingLastPathComponent().appendingPathComponent("\(stem) (\(index))" + (ext.isEmpty ? "" : ".\(ext)"))
            if !fm.fileExists(atPath: url.path) { return url }
        }
        return requested.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + "-" + requested.lastPathComponent)
    }

    func createFolder(remote: Bool) {
        guard !demoMode else { return }
        guard !remote || connected else { return }
        let alert = NSAlert(); alert.messageText = "新建\(remote ? "远程" : "本地")文件夹"
        alert.informativeText = "请输入文件夹名称"; alert.addButton(withTitle: "创建"); alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); field.stringValue = "未命名文件夹"
        alert.accessoryView = field; alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue
        guard RemotePath.safeName(name) else { alertMessage = "文件夹名称不能为空、包含 / 或使用 . 和 .."; return }
        if remote, let session = browser {
            let path = RemotePath.join(remotePath, name)
            Task {
                do { try await session.perform { try $0.mkdir(path) }; navigateRemote(remotePath) }
                catch { alertMessage = error.localizedDescription }
            }
        } else {
            do {
                let url = URL(fileURLWithPath: localPath).appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: url.path) else { throw SFTPError("同名文件或文件夹已存在") }
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false); refreshLocal()
            } catch { alertMessage = error.localizedDescription }
        }
    }

    func shutdown() {
        transferRefresh?.cancel(); browseCancellation?.cancel()
        browser?.stop()
        for job in jobs {
            job.cancellation.cancel(); job.session?.stop()
            job.completion?(SFTPError("应用已退出"))
        }
    }
}
