import AppKit
import Combine
import Foundation
import SwiftUI
import SFTPCore

/// Reproducible, offline main-thread workload. Never uses the user's directories or SSH hosts.
@MainActor
func runPerformanceChecks() -> Never {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let domain = "app.senda.performance-check.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: domain)!
    let model = AppModel(preferences: preferences, loadFiles: false, loadHosts: false)
    let entries: [FileEntry] = (0..<20_000).map { index -> FileEntry in
        let prefix = index % 5 == 0 ? ".hidden-" : "file-"
        let name = prefix + String(index) + ".txt"
        let size = UInt64(index) * 1024
        return FileEntry(name: name, path: "/fixture/\(index)", size: size, permissions: 0o100644, modified: Date(timeIntervalSince1970: 1_700_000_000))
    }
    model.localFiles = entries; model.remoteFiles = entries
    model.remoteSelection = [entries[17].path]
    var metrics: [String: Double] = ["directory_entries": Double(entries.count)]
    func measure(_ name: String, _ operation: () -> Void) {
        let start = ProcessInfo.processInfo.systemUptime
        operation()
        metrics[name] = (ProcessInfo.processInfo.systemUptime - start) * 1000
    }
    var count = 0
    measure("visible_reads_200_ms") {
        for _ in 0..<100 { count += model.visibleLocal.count + model.visibleRemote.count }
    }
    let view = FileTable(model: model, remote: true, entries: model.visibleRemote)
    let coordinator = view.makeCoordinator()
    let actualScroll = view.makeScrollView(coordinator: coordinator)
    coordinator.table?.reloadData()
    view.synchronizeSelection(coordinator: coordinator)
    measure("selection_sync_1000_ms") {
        for _ in 0..<1000 { view.synchronizeSelection(coordinator: coordinator) }
    }
    let job = TransferJob(host: "fixture", name: "transfer.bin", uploading: false, localURL: URL(fileURLWithPath: "/fixture/transfer.bin"), remotePath: "/fixture/transfer.bin")
    jobForPerformanceStart(model, job: job)
    var notifications = 0
    let observation = model.objectWillChange.sink { notifications += 1 }
    measure("progress_mutations_200_ms") {
        for index in 0..<200 {
            model.jobs[0].updateProgress(completed: UInt64(index * 1024), total: 1_000_000,
                                         at: Double(index) * 0.1)
        }
    }
    metrics["progress_window_notifications"] = Double(notifications)
    observation.cancel()

    // Layout the real SwiftUI hierarchy, including both native file tables and a running transfer.
    let hosting = NSHostingView(rootView: ContentView(model: model))
    hosting.frame = NSRect(x: 0, y: 0, width: 1250, height: 790)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    measure("hosted_progress_60_updates_ms") {
        for index in 0..<60 {
            model.jobs[0].updateProgress(completed: UInt64(200 * 1024 + index * 16384), total: 2_000_000,
                                         at: 20 + Double(index) * 0.1)
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            hosting.layoutSubtreeIfNeeded()
        }
    }
    metrics["visible_count_checksum"] = Double(count)
    metrics["selected_count"] = Double(coordinator.table?.selectedRowIndexes.count ?? 0)
    withExtendedLifetime(actualScroll) {}
    window.orderOut(nil)
    model.shutdown(); preferences.removePersistentDomain(forName: domain)
    let data = try! JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    if CommandLine.arguments.contains("--verify"), notifications != 0 || metrics["selected_count"] != 1 || count != 3_200_000 { exit(1) }
    exit(0)
}

@MainActor
private func jobForPerformanceStart(_ model: AppModel, job: TransferJob) {
    job.state = .running; job.hasProgress = true
    model.jobs = [job]
}
