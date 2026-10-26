import Foundation
#if DEBUG
@testable import SFTPCore
#else
import SFTPCore
#endif

final class ConfigurationTests: CheckCase {
    func testConcreteAliasesAndProxyDiscovery() {
        let hosts = SSHConfig.parse("""
        Host *
            User fallback
        Host dev-box dev-backup
            HostName localhost
            User developer
            ProxyCommand python3 /usr/local/bin/ssh-proxy %h %p
        Host wildcard-* !excluded
            User other
        Host "my-alias" # comment
            HostName=127.0.0.1
        Match host something
            User nope
        Host final
        """)
        expectEqual(hosts.map(\.alias), ["dev-box", "dev-backup", "my-alias", "final"])
        expectEqual(hosts[0].user, "developer")
        expectTrue(hosts[1].usesProxy)
        expectEqual(hosts[2].hostname, "127.0.0.1")
        expectFalse(hosts[3].usesProxy)
    }

    func testIncludesAvoidCycles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "Include extra-*\nHost first\n".write(to: root.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        try "Include config\nHost second\n ProxyJump bastion\n".write(to: root.appendingPathComponent("extra-one"), atomically: true, encoding: .utf8)
        expectEqual(SSHConfig.hosts(at: root.appendingPathComponent("config")).map(\.alias), ["second", "first"])
    }

    func testSafeNamesAndPaths() {
        for name in ["", ".", "..", "a/b", "a\0b"] { expectFalse(RemotePath.safeName(name)) }
        for name in ["中文 ' 文件.txt", ".env", "-rf", "a\nb"] { expectTrue(RemotePath.safeName(name)) }
        expectEqual(RemotePath.join("/", "a"), "/a")
        expectEqual(RemotePath.join("/a", "b"), "/a/b")
        expectEqual(RemotePath.parent("/a"), "/")
        expectThrows(try SFTPSession(host: "-oProxyCommand=evil"))
    }

    func testBinaryPacketBounds() throws {
#if DEBUG
        var packet = Packet(); packet.put(UInt32(0x12345678)); packet.put(UInt64(0xfedcba9876543210)); packet.put("你好 🌊")
        expectEqual(try packet.u32(), 0x12345678)
        expectEqual(try packet.u64(), 0xfedcba9876543210)
        expectEqual(try packet.string(), "你好 🌊")
        expectThrows(try packet.u32())
        var truncated = Packet(Data([0, 0, 0, 100, 1]))
        expectThrows(try truncated.data())
#endif
    }
}

final class SFTPIntegrationTests: CheckCase {
    private var root: URL!
    private var session: SFTPSession!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("senda-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
        session = try SFTPSession(serverExecutable: URL(fileURLWithPath: "/usr/libexec/sftp-server"), arguments: ["-d", root.path])
        try session.handshake()
    }
    override func tearDownWithError() throws { session?.stop(); try? FileManager.default.removeItem(at: root) }

    func testDirectoryAndSpecialNames() throws {
        let name = "中文 'quote' 空格\n换行"
        let path = root.appendingPathComponent(name).path
        try session.mkdir(path)
        let resolved = try session.realpath(".")
        let actualID = try FileManager.default.attributesOfItem(atPath: resolved)[.systemFileNumber] as? NSNumber
        let expectedID = try FileManager.default.attributesOfItem(atPath: root.path)[.systemFileNumber] as? NSNumber
        expectEqual(actualID, expectedID) // /var is a symlink to /private/var on macOS.
        let entries = try session.list(root.path)
        expectEqual(entries.map(\.name), [name]); expectTrue(entries[0].isDirectory)
        try session.rmdir(path)
        expectFalse(try session.exists(path))
        expectThrows(try session.list(root.appendingPathComponent("missing").path))
        expectEqual(try session.list(root.path).count, 0) // errors do not desynchronize later requests.
    }

    func testBinaryRoundTripAndCollisionProtection() throws {
        let bytes = Data((0..<(2 * 1024 * 1024 + 113)).map { UInt8(truncatingIfNeeded: $0 &* 17 &+ 3) })
        let source = root.appendingPathComponent("源文件 ' .bin")
        try bytes.write(to: source)
        let target = root.appendingPathComponent("remote.bin").path
        var uploaded: UInt64 = 0
        expectEqual(try session.upload(source, to: target, cancellation: Cancellation()) { uploaded = $0; _ = $1 }, target)
        expectEqual(uploaded, UInt64(bytes.count))
        let second = try session.upload(source, to: target, cancellation: Cancellation()) { _, _ in }
        expectEqual((second as NSString).lastPathComponent, "remote (2).bin")
        let local = root.appendingPathComponent("下载.bin")
        var downloaded: UInt64 = 0
        try session.download(target, to: local, cancellation: Cancellation()) { downloaded = $0; _ = $1 }
        expectEqual(downloaded, UInt64(bytes.count))
        expectEqual(try Data(contentsOf: local), bytes)
        expectThrows(try session.download(target, to: local, cancellation: Cancellation()) { _, _ in })
        expectEqual(try Data(contentsOf: local), bytes)
        expectFalse(try session.list(root.path).contains { $0.name.hasPrefix(".senda-") })
    }

    func testEmptyFileAndRecursiveFoldersSkipSymlinks() throws {
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("子目录"), withIntermediateDirectories: true)
        try Data().write(to: source.appendingPathComponent("zero"))
        try Data("hello".utf8).write(to: source.appendingPathComponent("子目录/a.txt"))
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("loop"), withDestinationURL: source)
        let target = root.appendingPathComponent("remote-folder").path
        try session.upload(source, to: target, cancellation: Cancellation()) { _, _ in }
        expectFalse(try session.exists(RemotePath.join(target, "loop")))
        let download = root.appendingPathComponent("download-folder")
        try session.download(target, to: download, cancellation: Cancellation()) { _, _ in }
        expectEqual(try Data(contentsOf: download.appendingPathComponent("zero")).count, 0)
        expectEqual(try String(contentsOf: download.appendingPathComponent("子目录/a.txt")), "hello")
    }

    func testWholeDirectoryProgress() throws {
        let source = root.appendingPathComponent("tree")
        let nested = source.appendingPathComponent("nested/empty")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let sizes = [700_013, 1_100_021, 0, 150_007]
        let paths = ["one.bin", "nested/two.bin", "nested/zero", "nested/three.bin"]
        for (name, size) in zip(paths, sizes) { try Data(repeating: UInt8(size % 255), count: size).write(to: source.appendingPathComponent(name)) }
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("loop"), withDestinationURL: source)
        let expected = UInt64(sizes.reduce(0, +))
        let remote = root.appendingPathComponent("target").path
        try session.mkdir(remote) // Exercise collision resolution at the root only.
        var uploadEvents: [(UInt64, UInt64)] = [], resolved: [String] = []
        let actual = try session.upload(source, to: remote, cancellation: Cancellation(), progress: { uploadEvents.append(($0, $1)) }, destinationResolved: { resolved.append($0) })
        expectEqual(resolved, [actual]); expectNotEqual(actual, remote)
        assertProgress(uploadEvents, expected: expected)
        let local = root.appendingPathComponent("download")
        var downloadEvents: [(UInt64, UInt64)] = []
        try session.download(actual, to: local, cancellation: Cancellation()) { downloadEvents.append(($0, $1)) }
        assertProgress(downloadEvents, expected: expected)
        for name in paths { expectEqual(try Data(contentsOf: source.appendingPathComponent(name)), try Data(contentsOf: local.appendingPathComponent(name))) }
        expectTrue(FileManager.default.fileExists(atPath: local.appendingPathComponent("nested/empty").path))
        expectFalse(FileManager.default.fileExists(atPath: local.appendingPathComponent("loop").path))
    }

    private func assertProgress(_ events: [(UInt64, UInt64)], expected: UInt64) {
        expectTrue(events.count > 2)
        expectEqual(events.first?.0, 0); expectEqual(events.last?.0, expected)
        expectTrue(events.allSatisfy { $0.1 == expected && $0.0 <= expected })
        expectTrue(zip(events, events.dropFirst()).allSatisfy { $0.0.0 <= $0.1.0 })
        expectTrue(events.contains { $0.0 > 0 && $0.0 < expected })
    }

    func testEmptyDirectoryProgressAndCancelledScan() throws {
        let source = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let remote = root.appendingPathComponent("empty-remote").path
        var events: [(UInt64, UInt64)] = []
        try session.upload(source, to: remote, cancellation: Cancellation()) { events.append(($0, $1)) }
        expectFalse(events.isEmpty); expectTrue(events.allSatisfy { $0 == (0, 0) })
        events = []
        try session.download(remote, to: root.appendingPathComponent("empty-local"), cancellation: Cancellation()) { events.append(($0, $1)) }
        expectFalse(events.isEmpty); expectTrue(events.allSatisfy { $0 == (0, 0) })
        let token = Cancellation(); token.cancel()
        let target = root.appendingPathComponent("cancelled-scan").path
        expectThrows(try session.upload(source, to: target, cancellation: token) { _, _ in recordFailure("Cancelled scan emitted progress") })
        expectFalse(try session.exists(target))
        expectThrows(try session.download(remote, to: URL(fileURLWithPath: target), cancellation: token) { _, _ in recordFailure("Cancelled scan emitted progress") })
        expectFalse(FileManager.default.fileExists(atPath: target))
    }

    func testCancellationCleansPartialFiles() throws {
        let source = root.appendingPathComponent("large.bin")
        try Data(repeating: 42, count: 3 * 1024 * 1024).write(to: source)
        let token = Cancellation()
        let remote = root.appendingPathComponent("cancelled.bin").path
        expectThrows(try session.upload(source, to: remote, cancellation: token) { completed, _ in if completed > 0 { token.cancel() } })
        expectFalse(try session.exists(remote))
        expectFalse(try session.list(root.path).contains { $0.name.hasPrefix(".senda-") })
        let downloadToken = Cancellation()
        let download = root.appendingPathComponent("cancelled-download.bin")
        expectThrows(try session.download(source.path, to: download, cancellation: downloadToken) { completed, _ in if completed > 0 { downloadToken.cancel() } })
        expectFalse(FileManager.default.fileExists(atPath: download.path))
        expectFalse(try session.list(root.path).contains { $0.name.hasPrefix(".senda-") })
    }

    func testPermissionErrorDoesNotReplaceTarget() throws {
        let original = root.appendingPathComponent("original")
        try Data("keep".utf8).write(to: original)
        let source = root.appendingPathComponent("source")
        try Data("new".utf8).write(to: source)
        let result = try session.upload(source, to: original.path, cancellation: Cancellation()) { _, _ in }
        expectNotEqual(result, original.path)
        expectEqual(try String(contentsOf: original), "keep")
        expectEqual(try String(contentsOfFile: result), "new")
    }

    func testStopInterruptsBlockedConnection() throws {
        let stalled = try SFTPSession(serverExecutable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        let done = expectation(description: "connection interrupted")
        stalled.queue.async {
            do { try stalled.handshake(); recordFailure("Expected connection interruption") } catch {}
            done.fulfill()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { stalled.stop() }
        wait(for: [done], timeout: 3)
    }

    func testCancelledListingKeepsConnectionUsable() throws {
        let cancellation = Cancellation(); cancellation.cancel()
        expectThrows(try session.list(root.path, cancellation: cancellation))
        expectEqual(try session.list(root.path).count, 0)
    }
}

final class RemoteSmokeTests: CheckCase {
    func testConfiguredSSHProxyRoundTrip() throws {
        guard let host = ProcessInfo.processInfo.environment["SENDA_TEST_SSH_HOST"] else { throw CheckSkip("Set SENDA_TEST_SSH_HOST to opt into remote SSH testing") }
        let session = try SFTPSession(host: host)
        defer { session.stop() }
        try session.handshake()
        let home = try session.realpath(ProcessInfo.processInfo.environment["SENDA_TEST_REMOTE_ROOT"] ?? "/tmp")
        _ = try session.list(home)
        let remote = RemotePath.join(home, ".senda-smoke-\(UUID().uuidString)")
        print("Temporary remote directory: \(remote)"); fflush(stdout)
        try session.mkdir(remote)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("senda-remote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? session.rmdir(remote); try? FileManager.default.removeItem(at: local) }
        let source = local.appendingPathComponent("中文 ' proxy test.bin")
        let bytes = Data((0..<131113).map { UInt8(truncatingIfNeeded: $0) })
        try bytes.write(to: source)
        let remoteFile = try session.upload(source, to: RemotePath.join(remote, source.lastPathComponent), cancellation: Cancellation()) { _, _ in }
        defer { try? session.remove(remoteFile) }
        let downloaded = local.appendingPathComponent("downloaded.bin")
        try session.download(remoteFile, to: downloaded, cancellation: Cancellation()) { _, _ in }
        expectEqual(try Data(contentsOf: downloaded), bytes)
        print("Remote ProxyCommand round trip passed: \(host) (\(bytes.count) bytes)")
    }
}
