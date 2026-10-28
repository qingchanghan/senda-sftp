import AppKit
import SFTPCore

/// Offline fixtures for documentation. No SSH configuration, directory reads or saved preferences.
@MainActor
enum DemoData {
    static func model() -> AppModel {
        let defaults = UserDefaults(suiteName: "app.senda.demo")!
        defaults.removePersistentDomain(forName: "app.senda.demo")
        let model = AppModel(preferences: defaults, loadFiles: false, demoMode: true)
        model.hosts = SSHConfig.parse("""
        Host atlas
            HostName atlas.example.com
            User developer
            ProxyJump bastion
        Host studio
            HostName studio.example.com
            User researcher
        Host build-box
            HostName build.example.com
            User ci
            ProxyCommand ssh bastion -W %h:%p
        Host staging
            HostName staging.example.com
            User deploy
        """)
        model.hostInput = "atlas"; model.connectedHost = "atlas"
        model.localPath = "/Users/developer/Projects"
        model.remotePath = "/home/developer/workspace"
        model.status = "已连接 · atlas"
        let date = Date(timeIntervalSince1970: 1_792_970_100)
        func entry(_ name: String, size: UInt64 = 0, directory: Bool = false, remote: Bool = false) -> FileEntry {
            FileEntry(name: name, path: (remote ? model.remotePath : model.localPath) + "/" + name,
                      size: size, permissions: directory ? 0o040755 : 0o100644, modified: date)
        }
        model.localFiles = [entry("checkpoints", directory: true), entry("datasets", directory: true), entry("notebooks", directory: true), entry("training-run", directory: true), entry("config.yaml", size: 2468), entry("evaluate.py", size: 12580), entry("README.md", size: 4096), entry("requirements.txt", size: 840)]
        model.remoteFiles = [entry("checkpoints", directory: true, remote: true), entry("datasets", directory: true, remote: true), entry("experiments", directory: true, remote: true), entry("training-run", directory: true, remote: true), entry("config.yaml", size: 2468, remote: true), entry("metrics.json", size: 38548, remote: true), entry("results.csv", size: 2621440, remote: true), entry("train.py", size: 18240, remote: true)]
        model.localSelection = [model.localPath + "/datasets", model.localPath + "/training-run"]
        func job(_ name: String, uploading: Bool, total: UInt64, completed: UInt64, state: TransferState) -> TransferJob {
            let job = TransferJob(host: "atlas", name: name, uploading: uploading,
                                  localURL: URL(fileURLWithPath: model.localPath + "/" + name), remotePath: model.remotePath + "/" + name, localMachine: "MacBook Pro")
            job.state = state; job.total = total; job.completed = completed; job.hasProgress = true
            job.resolvedDestinationPath = job.requestedDestinationPath
            return job
        }
        model.jobs = [job("training-run", uploading: true, total: 2_400_000_000, completed: 1_584_000_000, state: .running),
                      job("results.csv", uploading: false, total: 2_621_440, completed: 2_621_440, state: .done)]
        if CommandLine.arguments.contains("--demo-file") {
            if let file = model.localFiles.first(where: { $0.name == "config.yaml" }) {
                model.showLocation(BrowserLocation(directoryPath: model.localPath, entries: [file], file: file), remote: false)
            }
            if let file = model.remoteFiles.first(where: { $0.name == "results.csv" }) {
                model.showLocation(BrowserLocation(directoryPath: model.remotePath, entries: [file], file: file), remote: true)
            }
        }
        return model
    }
}
