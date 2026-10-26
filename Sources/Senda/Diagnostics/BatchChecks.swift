import AppKit
import Foundation
import SFTPCore

@MainActor
func runBatchChecks() -> Never {
    guard let index = CommandLine.arguments.firstIndex(of: "--batch-checks"), CommandLine.arguments.count > index + 1 else {
        fputs("Usage: Senda --batch-checks <ssh-host>\n", stderr); exit(2)
    }
    let host = CommandLine.arguments[index + 1]
    let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        let id = UUID().uuidString, domain = "app.senda.batch-check.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        let model = AppModel(preferences: preferences, loadFiles: false, loadHosts: false)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("senda-batch-\(id)")
        let remote = "/tmp/senda-batch-\(id)"
        var cleanupSession: SFTPSession?
        var createdRemote = false
        var result: Int32 = 0
        do {
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
            let source = local.appendingPathComponent("source"), target = local.appendingPathComponent("download"), promises = local.appendingPathComponent("promises")
            for url in [source, target, promises] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            let folder = source.appendingPathComponent("子目录")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let a = source.appendingPathComponent("中文 ' a.txt"), b = source.appendingPathComponent("b.bin")
            try Data("Senda multi-selection 🌊\n".utf8).write(to: a)
            try Data((0..<131113).map { UInt8(truncatingIfNeeded: $0) }).write(to: b)
            try Data("Nested batch item\n".utf8).write(to: folder.appendingPathComponent("inside.txt"))
            try Data(repeating: 51, count: 700_013).write(to: folder.appendingPathComponent("weights.bin"))
            let sourceEntries = [FileEntry(name: folder.lastPathComponent, path: folder.path, permissions: 0o040755), FileEntry(name: a.lastPathComponent, path: a.path, permissions: 0o100644), FileEntry(name: b.lastPathComponent, path: b.path, permissions: 0o100644)]
            let session = try SFTPSession(host: host)
            cleanupSession = session
            try await session.perform { try $0.handshake(); try $0.mkdir(remote) }
            createdRemote = true
            print("Temporary remote directory: \(remote)"); fflush(stdout)
            model.connect(host)
            try await waitUntil(model) { model.connected && !model.isConnecting && !model.isRemoteLoading }
            model.navigateRemote(remote)
            try await waitUntil(model) { !model.isRemoteLoading && model.remotePath == remote }
            let uploadView = FileTable(model: model, remote: false, entries: sourceEntries)
            let uploadCoordinator = uploadView.makeCoordinator()
            let board = NSPasteboard(name: .init("app.senda.batch.\(id)"))
            defer { board.releaseGlobally() }
            let writers = sourceEntries.indices.compactMap { uploadCoordinator.tableView(NSTableView(), pasteboardWriterForRow: $0) }
            guard writers.count == 3, board.writeObjects(writers) else { throw SFTPError("Batch upload drag payload failed") }
            let destination = FileTable(model: model, remote: true, entries: [])
            guard destination.makeCoordinator().acceptDrop(from: board, row: -1), model.jobs.count == 3 else { throw SFTPError("Batch upload did not enqueue every selected item") }
            try await waitUntil(model) { model.activeJobs == 0 }
            try verifyJobs(model)
            let expectedFolderSize = UInt64(700_013 + Data("Nested batch item\n".utf8).count)
            guard let folderUpload = model.jobs.first(where: { $0.name == folder.lastPathComponent }), folderUpload.total == expectedFolderSize, folderUpload.completed == expectedFolderSize else { throw SFTPError("Queue lost aggregate directory upload progress") }
            print("PASS directory queue stores aggregate upload total and final progress")
            print("PASS one multi-item drop → three completed uploads (including folder)"); fflush(stdout)
            guard model.transferConnectionsOpened == 1 else { throw SFTPError("The upload batch did not reuse its SSH connection") }
            print("PASS three uploads share one SSH/ProxyCommand connection"); fflush(stdout)
            model.navigateRemote(remote)
            try await waitUntil(model) { !model.isRemoteLoading && model.remoteFiles.count == 3 }
            model.selectAll(remote: true)
            let selected = model.remoteSelection
            model.navigateRemote(remote)
            try await waitUntil(model) { !model.isRemoteLoading }
            guard model.remoteSelection == selected, selected.count == 3 else { throw SFTPError("Remote refresh lost multi-selection") }
            print("PASS remote refresh preserves all selected paths"); fflush(stdout)

            let remoteView = FileTable(model: model, remote: true, entries: model.visibleRemote)
            let remoteCoordinator = remoteView.makeCoordinator()
            let remoteWriters = model.visibleRemote.indices.compactMap { remoteCoordinator.tableView(NSTableView(), pasteboardWriterForRow: $0) as? NSFilePromiseProvider }
            board.clearContents()
            guard remoteWriters.count == 3, board.writeObjects(remoteWriters) else { throw SFTPError("Batch remote drag payload failed") }
            model.localPath = target.path
            let connectionsBeforeDownload = model.transferConnectionsOpened
            let localView = FileTable(model: model, remote: false, entries: [])
            guard localView.makeCoordinator().acceptDrop(from: board, row: -1), model.jobs.count == 6 else { throw SFTPError("Batch download did not enqueue every selected item") }
            try await waitUntil(model) { model.activeJobs == 0 }
            try verifyJobs(model)
            guard let folderDownload = model.jobs.last(where: { $0.name == folder.lastPathComponent }), folderDownload.total == expectedFolderSize, folderDownload.completed == expectedFolderSize else { throw SFTPError("Queue lost aggregate directory download progress") }
            print("PASS directory queue stores aggregate download total and final progress")
            try compareDirectories(source, target)
            guard model.transferConnectionsOpened - connectionsBeforeDownload == 1 else { throw SFTPError("The download batch did not reuse its SSH connection") }
            print("PASS one multi-item drop → three completed downloads; all bytes identical"); fflush(stdout)
            print("PASS three downloads share one SSH/ProxyCommand connection"); fflush(stdout)

            // Execute every file promise's completion path, just as AppKit does after a Finder drop.
            for promise in remoteWriters {
                guard let delegate = promise.delegate else { throw SFTPError("Batch promise delegate was released") }
                let name = delegate.filePromiseProvider(promise, fileNameForType: promise.fileType)
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    delegate.filePromiseProvider(promise, writePromiseTo: promises.appendingPathComponent(name)) { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    }
                }
            }
            try compareDirectories(source, promises)
            print("PASS all native file promises download the selected files and folder"); fflush(stdout)

            let cancelTarget = local.appendingPathComponent("cancel-check")
            try FileManager.default.createDirectory(at: cancelTarget, withIntermediateDirectories: true)
            let startIndex = model.jobs.count
            model.enqueueDownloads(model.visibleRemote.map { ($0, host) }, directory: cancelTarget)
            let cancelled = model.jobs[startIndex + 1]
            model.cancel(cancelled.id)
            try await waitUntil(model) { model.activeJobs == 0 }
            guard cancelled.state == .cancelled,
                  model.jobs[startIndex].state == .done,
                  model.jobs[startIndex + 2].state == .done,
                  !FileManager.default.fileExists(atPath: cancelTarget.appendingPathComponent(cancelled.name).path) else { throw SFTPError("Cancelling a queued item affected the other transfers") }
            print("PASS cancelling a queued item preserves the remaining batch and active count"); fflush(stdout)

            guard cancelled.sourceMachine == "远程 · \(host)", cancelled.resolvedDestinationPath == nil,
                  cancelled.detailsText.contains("目标路径（计划）") else { throw SFTPError("Cancelled queued details lost their planned endpoints") }
            let remoteA = RemotePath.join(remote, a.lastPathComponent)
            model.upload([a], to: remote)
            try await waitUntil(model) { model.activeJobs == 0 }
            let renamedUpload = model.jobs.last!
            let expectedRemote = RemotePath.join(remote, "中文 ' a (2).txt")
            guard renamedUpload.state == .done, renamedUpload.sourcePath == a.path,
                  renamedUpload.sourceMachine.hasPrefix("本机 · "), renamedUpload.destinationMachine == "远程 · \(host)",
                  renamedUpload.destinationPath == expectedRemote else { throw SFTPError("Upload details do not describe the renamed remote destination") }
            let remoteSize = try await session.perform { try $0.stat(expectedRemote).size }
            guard remoteSize == UInt64(try Data(contentsOf: a).count) else { throw SFTPError("Upload detail destination does not exist with expected content size") }
            print("PASS upload details show the original local source and actual renamed remote destination"); fflush(stdout)

            let entry = FileEntry(name: a.lastPathComponent, path: remoteA, permissions: 0o100644)
            model.enqueueDownload(entry, directory: target, host: host)
            try await waitUntil(model) { model.activeJobs == 0 }
            let renamedDownload = model.jobs.last!
            let expectedLocal = target.appendingPathComponent("中文 ' a (2).txt")
            guard renamedDownload.state == .done, renamedDownload.sourcePath == remoteA,
                  renamedDownload.sourceMachine == "远程 · \(host)", renamedDownload.destinationMachine.hasPrefix("本机 · "),
                  renamedDownload.destinationPath == expectedLocal.path,
                  try Data(contentsOf: expectedLocal) == Data(contentsOf: a) else { throw SFTPError("Download details do not describe the actual renamed local destination") }
            guard model.jobs.filter({ $0.localURL.deletingLastPathComponent() == promises }).allSatisfy({ $0.destinationPath == $0.localURL.path && $0.resolvedDestinationPath != nil }) else { throw SFTPError("Finder promise details lost the exact destination") }
            model.connectedHost = "another-host"; model.localPath = source.path; model.remotePath = "/another-directory"
            guard renamedDownload.sourceMachine == "远程 · \(host)", renamedDownload.destinationPath == expectedLocal.path,
                  renamedDownload.detailsText.contains(expectedLocal.path), renamedDownload.detailsText.contains("原定目标路径：") else { throw SFTPError("Changing the current host or directory changed historical transfer details") }
            print("PASS download collision, exact Finder destination and historical endpoint snapshots"); fflush(stdout)

            let missing = FileEntry(name: "missing.txt", path: RemotePath.join(remote, "missing.txt"), permissions: 0o100644)
            model.enqueueDownload(missing, directory: target, host: host)
            try await waitUntil(model) { model.activeJobs == 0 }
            let failed = model.jobs.last!
            guard failed.state == .failed, failed.sourcePath == missing.path,
                  failed.destinationPath == target.appendingPathComponent(missing.name).path,
                  failed.detailsText.contains("错误："), !failed.error.isEmpty else { throw SFTPError("Failed transfer details lost endpoints or error") }
            print("PASS failed transfer details retain both endpoints and the error"); fflush(stdout)
        } catch { fputs("Batch checks failed: \(error.localizedDescription)\n", stderr); result = 1 }
        model.shutdown()
        if let session = cleanupSession, createdRemote {
            do { try await session.perform { try removeTestDirectory($0, path: remote) } }
            catch { fputs("Test cleanup failed at \(remote): \(error.localizedDescription)\n", stderr); result = 1 }
        }
        cleanupSession?.stop()
        try? FileManager.default.removeItem(at: local)
        preferences.removePersistentDomain(forName: domain)
        print("Batch checks complete; temporary data cleaned up"); fflush(stdout)
        exit(result)
    }
    app.run(); exit(1)
}

@MainActor
private func waitUntil(_ model: AppModel, condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(120)
    while !condition() {
        if let error = model.alertMessage { throw SFTPError(error) }
        guard Date() < deadline else { throw SFTPError("Batch check timed out") }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
}

@MainActor
private func verifyJobs(_ model: AppModel) throws {
    if let failed = model.jobs.first(where: { $0.state != .done }) { throw SFTPError("\(failed.name): \(failed.error)") }
}

private func compareDirectories(_ source: URL, _ destination: URL) throws {
    let expected = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])
    let actual = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
    guard Set(expected.map(\.lastPathComponent)) == Set(actual.map(\.lastPathComponent)) else { throw SFTPError("Batch filenames differ") }
    for child in expected {
        let other = destination.appendingPathComponent(child.lastPathComponent)
        if try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { try compareDirectories(child, other) }
        else if try Data(contentsOf: child) != Data(contentsOf: other) { throw SFTPError("Batch file bytes differ: \(child.lastPathComponent)") }
    }
}

private func removeTestDirectory(_ session: SFTPSession, path: String) throws {
    for entry in try session.list(path) {
        if entry.isDirectory { try removeTestDirectory(session, path: entry.path) }
        else { try session.remove(entry.path) }
    }
    try session.rmdir(path)
}
