import Foundation
import Combine
import SFTPCore

enum TransferState: String { case waiting = "等待中", running = "传输中", done = "已完成", failed = "失败", cancelled = "已取消" }

@MainActor
final class TransferJob: ObservableObject, Identifiable {
    let id = UUID()
    let host: String
    let name: String
    let uploading: Bool
    let localURL: URL
    let remotePath: String
    let localMachine: String
    let cancellation = Cancellation()
    @Published var state = TransferState.waiting
    @Published var completed: UInt64 = 0
    @Published var total: UInt64 = 0
    @Published var hasProgress = false
    @Published var error = ""
    @Published var cancellationRequested = false
    @Published var resolvedDestinationPath: String?
    var startedAt: Date?
    var session: SFTPSession?
    var completion: ((Error?) -> Void)?
    private var rate = TransferRate()

    init(host: String, name: String, uploading: Bool, localURL: URL, remotePath: String, localMachine: String = ProcessInfo.processInfo.hostName) {
        self.localMachine = localMachine
        self.host = host; self.name = name; self.uploading = uploading
        self.localURL = localURL; self.remotePath = remotePath
    }

    var sourceMachine: String { uploading ? "本机 · \(localMachine)" : "远程 · \(host)" }
    var destinationMachine: String { uploading ? "远程 · \(host)" : "本机 · \(localMachine)" }
    var sourcePath: String { uploading ? localURL.path : remotePath }
    var requestedDestinationPath: String { uploading ? remotePath : localURL.path }
    var destinationPath: String { resolvedDestinationPath ?? requestedDestinationPath }
    var destinationPathLabel: String { resolvedDestinationPath == nil ? "目标路径（计划）" : "目标路径" }
    var showsSpeed: Bool { state == .running && hasProgress && !cancellationRequested }

    func updateProgress(completed: UInt64, total: UInt64, at time: TimeInterval) {
        guard state == .running, completed >= self.completed else { return }
        rate.record(completed: completed, at: time)
        if !hasProgress { hasProgress = true }
        if self.completed != completed { self.completed = completed }
        if self.total != total { self.total = total }
    }

    func speedText(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> String? {
        guard showsSpeed else { return nil }
        return rate.bytesPerSecond(at: time).map(TransferRateFormatter.string) ?? "测速中…"
    }

    var detailsText: String {
        var lines = ["文件：\(name)", "状态：\(state.rawValue)",
                     "源机器：\(sourceMachine)", "源路径：\(sourcePath)",
                     "目标机器：\(destinationMachine)", "\(destinationPathLabel)：\(destinationPath)"]
        if let speed = speedText() { lines.append("\(uploading ? "上传" : "下载")速度：\(speed)") }
        if destinationPath != requestedDestinationPath { lines.append("原定目标路径：\(requestedDestinationPath)") }
        if !error.isEmpty { lines.append("错误：\(error)") }
        return lines.joined(separator: "\n")
    }
}
