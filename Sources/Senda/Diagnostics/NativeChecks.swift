import AppKit
import Foundation
import SFTPCore

/// Developer integration check for the exact pasteboard and file-promise path used by Finder.
@MainActor
func runNativeChecks() -> Never {
    let arguments = CommandLine.arguments
    guard let offset = arguments.firstIndex(of: "--native-checks"), arguments.count > offset + 3 else {
        fputs("Usage: Senda --native-checks <ssh-host> <remote-directory> <local-source-file>\n", stderr); exit(2)
    }
    let host = arguments[offset + 1], directory = arguments[offset + 2]
    let source = URL(fileURLWithPath: arguments[offset + 3])
    let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        let domain = "app.senda.native-check.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        let model = AppModel(preferences: preferences, loadFiles: false, loadHosts: false)
        defer { model.shutdown(); preferences.removePersistentDomain(forName: domain) }
        do {
            let local = FileEntry(name: source.lastPathComponent, path: source.path, permissions: 0o100644)
            let localTable = FileTable(model: model, remote: false, entries: [local])
            let localCoordinator = localTable.makeCoordinator()
            let board = NSPasteboard(name: .init("app.senda.check.\(UUID().uuidString)"))
            defer { board.releaseGlobally() }
            guard let localWriter = localCoordinator.tableView(NSTableView(), pasteboardWriterForRow: 0), board.writeObjects([localWriter]),
                  let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], urls.first?.standardizedFileURL.path == source.standardizedFileURL.path else { throw SFTPError("Local file drag payload failed") }
            print("PASS local file URL pasteboard round trip"); fflush(stdout)

            model.connect(host)
            let deadline = Date().addingTimeInterval(90)
            while !model.connected || model.isConnecting {
                if let error = model.alertMessage { throw SFTPError(error) }
                guard Date() < deadline else { throw SFTPError("Native check connection timeout") }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            model.navigateRemote(directory)
            while model.isRemoteLoading {
                guard Date() < deadline else { throw SFTPError("Native check listing timeout") }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let remote = model.remoteFiles.first(where: { $0.name == source.lastPathComponent }) else { throw SFTPError("Upload source file before running native checks") }
            let remoteTable = FileTable(model: model, remote: true, entries: [remote])
            let coordinator = remoteTable.makeCoordinator()
            guard let promise = coordinator.tableView(NSTableView(), pasteboardWriterForRow: 0) as? NSFilePromiseProvider else { throw SFTPError("Remote file promise missing") }
            board.clearContents()
            guard board.writeObjects([promise]) else { throw SFTPError("Cannot write native file promise") }
            print("PASS remote file promise + custom drag payload"); fflush(stdout)
            let destination = source.deletingLastPathComponent().appendingPathComponent("promise-check-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: destination) }
            guard let delegate = promise.delegate else { throw SFTPError("Native file promise delegate was released") }
            let name = delegate.filePromiseProvider(promise, fileNameForType: "public.data")
            guard name == source.lastPathComponent else { throw SFTPError("Native promise filename differs") }
            let result = destination.appendingPathComponent(name)
            // Exercise the exact delegate callback AppKit invokes after a Finder drop.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.filePromiseProvider(promise, writePromiseTo: result) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            guard try Data(contentsOf: result) == Data(contentsOf: source) else { throw SFTPError("Native promise download bytes differ") }
            print("PASS native file-promise delegate → SSH ProxyCommand → downloaded bytes"); fflush(stdout)
            model.shutdown(); preferences.removePersistentDomain(forName: domain); exit(0)
        } catch {
            model.shutdown(); preferences.removePersistentDomain(forName: domain); fputs("Native checks failed: \(error.localizedDescription)\n", stderr); exit(1)
        }
    }
    app.run(); exit(1)
}
