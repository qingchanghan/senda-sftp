import AppKit
import Combine
import Foundation

@MainActor
func runSpeedChecks() -> Never {
    NSApplication.shared.setActivationPolicy(.prohibited)
    var failures = 0, count = 0
    @MainActor func check(_ value: @autoclosure () -> Bool, _ name: String) {
        count += 1
        if value() { print("PASS \(name)") }
        else { failures += 1; fputs("FAIL \(name)\n", stderr) }
    }
    let domain = "app.senda.speed-check.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: domain)!
    let model = AppModel(preferences: preferences, loadFiles: false, loadHosts: false)
    let job = TransferJob(host: "fixture", name: "tree", uploading: false,
                          localURL: URL(fileURLWithPath: "/fixture/tree"), remotePath: "/fixture/tree")
    model.jobs = [job]
    var notifications = 0
    let observation = model.objectWillChange.sink { notifications += 1 }
    check(job.speedText(at: 10) == nil, "waiting transfers have no speed")
    job.state = .running
    check(job.speedText(at: 10) == nil, "directory planning is excluded from speed")
    job.updateProgress(completed: 0, total: 2_000_000, at: 10)
    check(job.speedText(at: 10) == "测速中…", "first progress sample waits for elapsed time")
    job.updateProgress(completed: 500_000, total: 2_000_000, at: 10.5)
    check(job.speedText(at: 10.5) == "1 MB/s", "download speed uses actual cumulative bytes")
    check(job.speedText(at: 12.5) == "0 B/s", "a stalled download reaches zero without new callbacks")
    job.updateProgress(completed: 100_000, total: 2_000_000, at: 10.2)
    check(job.completed == 500_000 && job.speedText(at: 10.5) == "1 MB/s", "late callbacks cannot regress progress or speed")
    check(job.detailsText.contains("下载速度："), "copied details include current download speed")
    job.cancellationRequested = true
    check(job.speedText(at: 10.5) == nil, "cancelling immediately hides live speed")
    job.cancellationRequested = false
    for state: TransferState in [.done, .failed, .cancelled] {
        job.state = state
        check(job.speedText(at: 10.5) == nil && !job.detailsText.contains("下载速度："), "\(state.rawValue) hides stale speed")
    }
    job.updateProgress(completed: 1_000_000, total: 2_000_000, at: 11)
    check(job.completed == 500_000 && !job.showsSpeed, "late callbacks cannot resurrect completed jobs")
    check(notifications == 0, "speed and progress emit no model-wide notifications")
    observation.cancel()
    let upload = TransferJob(host: "fixture", name: "file", uploading: true,
                             localURL: URL(fileURLWithPath: "/fixture/file"), remotePath: "/fixture/file")
    upload.state = .running
    upload.updateProgress(completed: 0, total: 2_000_000_000, at: 0)
    upload.updateProgress(completed: 1_500_000_000, total: 2_000_000_000, at: 1)
    check(upload.speedText(at: 1) == "1.5 GB/s", "uploads use the same adaptive speed display")
    model.shutdown(); preferences.removePersistentDomain(forName: domain)
    print("Speed checks: \(count) checks, \(failures) failures")
    exit(failures == 0 ? 0 : 1)
}
