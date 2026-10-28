import AppKit
import Darwin
import Foundation
import SFTPCore

/// Real model + SFTP queue checks using disposable files and the local SFTP server.
/// No SSH configuration or live remote host is read.
@MainActor
func runAddressChecks() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("senda-address-\(UUID().uuidString)")
        let domain = "app.senda.address-check.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        let local = root.appendingPathComponent("local"), remote = root.appendingPathComponent("remote")
        let nested = remote.appendingPathComponent("nested")
        preferences.set(local.path, forKey: "localPath")
        let model = AppModel(preferences: preferences, loadFiles: false, loadHosts: false,
                             sessionFactory: { _, _, _ in
            try SFTPSession(serverExecutable: URL(fileURLWithPath: "/usr/libexec/sftp-server"), arguments: ["-d", remote.path])
        })
        var failures = 0, count = 0
        @MainActor func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
            count += 1
            do {
                if try condition() { print("PASS \(name)") }
                else { failures += 1; fputs("FAIL \(name)\n", stderr) }
            } catch { failures += 1; fputs("FAIL \(name): \(error.localizedDescription)\n", stderr) }
            fflush(stdout)
        }
        @MainActor func wait(_ description: String, until condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(15)
            while !condition() {
                guard Date() < deadline else { throw SFTPError("Timed out: \(description)") }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        @MainActor func navigate(_ path: String, remote: Bool = false) async throws {
            model.alertMessage = nil
            if remote { model.navigateRemote(path) } else { model.navigateLocal(path) }
            try await wait("navigate \(path)") { remote ? !model.isRemoteLoading : !model.isLocalLoading }
        }
        @MainActor func cleanup() {
            model.shutdown()
            preferences.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        func canonical(_ url: URL) -> String {
            // Foundation displays /var while OpenSSH REALPATH returns /private/var.
            guard let resolved = realpath(url.path, nil) else { return url.path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        do {
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let name = "训练 ' sample %#?.bin"
            let source = local.appendingPathComponent(name), target = nested.appendingPathComponent(name)
            let bytes = Data((0..<100_013).map { UInt8(truncatingIfNeeded: $0 * 13) })
            let original = Data("existing remote file".utf8)
            try bytes.write(to: source); try original.write(to: target)
            let hidden = local.appendingPathComponent(".hidden"), remoteHidden = nested.appendingPathComponent(".hidden")
            try Data().write(to: hidden); try Data().write(to: remoteHidden)
            let targetPath = canonical(target), nestedPath = canonical(nested)

            try await navigate(source.path)
            check(model.alertMessage == nil && model.localAddressFile?.path == source.path, "local file address resolves Unicode, spaces and punctuation")
            check(model.localPath == local.path && model.localAddress == source.path, "local address and committed directory remain separate")
            check(model.selectedEntries(remote: false).map(\.path) == [source.path], "addressed local file is selected")
            check(preferences.string(forKey: "localPath") == local.path, "preferences remember the parent, never a file as a directory")
            check(model.jobs.isEmpty && !model.canTransferAddressFile(remote: false), "navigation never uploads automatically; disconnected upload is disabled")
            try await navigate(source.absoluteString)
            check(model.alertMessage == nil && model.localAddressFile?.path == source.path, "local file URL decodes percent-encoded characters")
            try await navigate(name)
            check(model.localAddressFile?.path == source.path && model.alertMessage == nil, "relative local file uses the pane's directory")
            try await navigate(hidden.path)
            check(model.visibleLocal.map(\.path) == [hidden.path] && model.localAddressFile?.size == 0 && !model.showHidden, "explicit hidden and empty file works without changing hidden-file preference")
            try await navigate(local.path)
            check(model.localAddressFile == nil && !model.visibleLocal.contains(where: { $0.name == ".hidden" }), "return to local folder restores normal filtering")
            try await navigate(source.path)
            try Data([1, 2, 3]).write(to: source)
            model.refreshLocal(); try await wait("local refresh") { !model.isLocalLoading }
            check(model.localAddressFile?.size == 3 && model.localAddress == source.path, "refresh updates file metadata while retaining file mode")
            try bytes.write(to: source)
            try await navigate(local.appendingPathComponent("missing").path)
            check(model.alertMessage != nil && model.localPath == local.path && model.localAddress == source.path, "missing local address preserves the previous valid destination")
            try await navigate("")
            check(model.alertMessage != nil && model.localPath == local.path, "empty addresses do not replace the current location")
            try await navigate("file://other-machine/tmp/file")
            check(model.alertMessage != nil, "a file URL cannot silently point at a different machine")

            let fileLink = local.appendingPathComponent("file-link"), folderLink = local.appendingPathComponent("folder-link")
            try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: source)
            try FileManager.default.createSymbolicLink(at: folderLink, withDestinationURL: nested)
            try await navigate(fileLink.path)
            check(model.alertMessage != nil && model.localAddress != fileLink.path, "local file symlink is explicitly rejected")
            try await navigate(folderLink.path)
            check(model.alertMessage == nil && model.localAddressFile == nil && model.localPath == nested.path, "local directory symlink remains browsable")
            let fifo = local.appendingPathComponent("named-pipe")
            guard mkfifo(fifo.path, 0o600) == 0 else { throw SFTPError("Cannot create FIFO fixture") }
            try await navigate(fifo.path)
            check(model.alertMessage != nil, "local special files are rejected without blocking")
            model.navigateLocal(source.path); model.navigateLocal(local.path)
            try await wait("latest local navigation") { !model.isLocalLoading }
            try await Task.sleep(nanoseconds: 50_000_000)
            check(model.localAddressFile == nil && model.localPath == local.path, "latest local navigation wins")

            model.connect("fixture")
            try await wait("connect") { !model.isConnecting && !model.isRemoteLoading }
            guard model.connected else { throw SFTPError(model.alertMessage ?? "Local SFTP connection failed") }
            try await navigate(target.path, remote: true)
            check(model.alertMessage == nil && model.remoteAddressFile?.path == targetPath, "remote full file address resolves via SFTP metadata")
            check(model.remotePath == nestedPath && model.remoteAddress == targetPath, "remote file path is separate from destination directory")
            check(model.remoteSelection == [targetPath] && preferences.string(forKey: "remotePath.fixture") == nestedPath, "remote file selection and remembered parent are correct")
            try await navigate(name, remote: true)
            check(model.remoteAddressFile?.path == targetPath && model.alertMessage == nil, "relative remote file uses the pane's directory, not login directory")
            try await navigate("~/nested/.hidden", remote: true)
            check(model.remoteAddressFile?.path == canonical(remoteHidden) && model.visibleRemote.count == 1 && !model.showHidden, "remote home and hidden empty file resolve explicitly")
            try await navigate(target.path, remote: true)
            try await navigate(nested.appendingPathComponent("missing").path, remote: true)
            check(model.alertMessage != nil && model.remoteAddress == targetPath && model.remotePath == nestedPath, "missing remote address preserves the previous location")
            try await navigate(fileLink.path, remote: true)
            check(model.alertMessage != nil && model.remoteAddress == targetPath, "remote file symlink is explicitly rejected")
            try await navigate(fifo.path, remote: true)
            check(model.alertMessage != nil, "remote special files are rejected")
            try await navigate(folderLink.path, remote: true)
            check(model.remoteAddressFile == nil && model.remotePath == nestedPath, "remote directory symlink remains browsable")

            // Execute-only parents can still contain readable files. Do not require READDIR.
            let privateParent = root.appendingPathComponent("no-list"), readable = privateParent.appendingPathComponent("readable.bin")
            try FileManager.default.createDirectory(at: privateParent, withIntermediateDirectories: true)
            try bytes.write(to: readable)
            try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: privateParent.path)
            do {
                defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: privateParent.path) }
                try await navigate(readable.path)
                check(model.alertMessage == nil && model.localAddressFile?.size == UInt64(bytes.count), "local file does not require listing its parent")
                try await navigate(readable.path, remote: true)
                check(model.alertMessage == nil && model.remoteAddressFile?.size == UInt64(bytes.count), "remote file does not require listing its parent")
            }
            try await navigate(source.path)
            try await navigate(target.path, remote: true)
            check(model.jobs.isEmpty, "all address resolutions remain read-only")
            model.isRemoteLoading = true; model.transferAddressFile(remote: false)
            check(model.jobs.isEmpty, "transfer waits until the destination finishes resolving")
            model.isRemoteLoading = false
            model.alertMessage = nil; model.transferAddressFile(remote: false)
            guard let upload = model.jobs.last else { throw SFTPError("No upload queued") }
            try await wait("upload and refresh") { upload.state == .done || upload.state == .failed }
            check(upload.state == .done, "addressed local file uploads through the real queue")
            guard let uploadedPath = upload.resolvedDestinationPath else { throw SFTPError("No upload destination") }
            let uploaded = try Data(contentsOf: URL(fileURLWithPath: uploadedPath))
            check(uploaded == bytes && uploadedPath != targetPath, "upload uses the opposite parent and preserves its selected file on collision")
            check(try Data(contentsOf: target) == original, "existing remote file is unchanged")
            try await wait("post-upload browse") { !model.isRemoteLoading }
            check(model.remoteAddressFile?.path == targetPath, "automatic transfer refresh preserves remote file mode")
            model.transferAddressFile(remote: true)
            guard let download = model.jobs.last, download.id != upload.id else { throw SFTPError("No download queued") }
            try await wait("download") { download.state == .done || download.state == .failed }
            check(download.state == .done, "addressed remote file downloads through the real queue")
            guard let downloadedPath = download.resolvedDestinationPath else { throw SFTPError("No download destination") }
            check(try Data(contentsOf: URL(fileURLWithPath: downloadedPath)) == original && downloadedPath != source.path, "download uses the local parent and collision-safe name")
            check(try Data(contentsOf: source) == bytes, "existing local file is unchanged")
            try await wait("post-download browse") { !model.isLocalLoading }
            check(model.localAddressFile?.path == source.path, "automatic transfer refresh preserves local file mode")
            model.navigateRemote(target.path); model.navigateRemote(remote.path)
            try await wait("latest remote navigation") { !model.isRemoteLoading }
            check(model.remoteAddressFile == nil && model.remotePath == canonical(remote), "latest remote navigation wins and returns to folders")
            model.navigateRemote(target.path); model.disconnect()
            try await Task.sleep(nanoseconds: 100_000_000)
            check(model.remoteAddressFile == nil && model.remoteFiles.isEmpty && !model.connected, "disconnect cannot resurrect an in-flight file address")
        } catch {
            failures += 1; fputs("FAIL address checks: \(error.localizedDescription)\n", stderr)
        }
        cleanup()
        print("Address checks: \(count) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
    app.run(); exit(1)
}
