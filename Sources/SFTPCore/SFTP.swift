import Foundation
import Darwin

public struct SFTPError: LocalizedError, Sendable {
    public let code: UInt32
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String, code: UInt32 = 0) { self.message = message; self.code = code }
}

public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public func check() throws { if isCancelled { throw SFTPError("传输已取消", code: 1000) } }
}

struct Packet {
    var bytes = Data()
    var offset = 0
    init(_ bytes: Data = Data()) { self.bytes = bytes }
    mutating func put(_ value: UInt8) { bytes.append(value) }
    mutating func put(_ value: UInt32) {
        var number = value.bigEndian
        withUnsafeBytes(of: &number) { bytes.append(contentsOf: $0) }
    }
    mutating func put(_ value: UInt64) {
        var number = value.bigEndian
        withUnsafeBytes(of: &number) { bytes.append(contentsOf: $0) }
    }
    mutating func put(_ value: String) { put(Data(value.utf8)) }
    mutating func put(_ value: Data) { put(UInt32(value.count)); bytes.append(value) }
    mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, count <= bytes.count - offset else { throw SFTPError("SFTP 返回了不完整的数据包") }
        let value = bytes.subdata(in: offset..<(offset + count)); offset += count
        return value
    }
    mutating func byte() throws -> UInt8 { try take(1)[0] }
    mutating func u32() throws -> UInt32 { try take(4).reduce(0) { ($0 << 8) | UInt32($1) } }
    mutating func u64() throws -> UInt64 { try take(8).reduce(0) { ($0 << 8) | UInt64($1) } }
    mutating func data() throws -> Data { try take(Int(u32())) }
    mutating func string() throws -> String {
        guard let string = String(data: try data(), encoding: .utf8) else { throw SFTPError("暂不支持非 UTF-8 文件名") }
        return string
    }
    mutating func attrs(name: String, path: String) throws -> FileEntry {
        let flags = try u32()
        let size = flags & 1 != 0 ? try u64() : 0
        if flags & 2 != 0 { _ = try u32(); _ = try u32() }
        let mode = flags & 4 != 0 ? try u32() : 0
        var modified: Date?
        if flags & 8 != 0 { _ = try u32(); modified = Date(timeIntervalSince1970: TimeInterval(try u32())) }
        if flags & 0x80000000 != 0 {
            let count = try u32()
            guard count < 10000 else { throw SFTPError("SFTP 属性数量异常") }
            for _ in 0..<count { _ = try data(); _ = try data() }
        }
        return FileEntry(name: name, path: path, size: size, permissions: mode, modified: modified)
    }
}

/// All protocol operations run on `queue`; stop() can interrupt a blocked SSH connection.
public final class SFTPSession: @unchecked Sendable {
    public let queue = DispatchQueue(label: "senda.sftp.\(UUID().uuidString)", qos: .userInitiated)
    private let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let stateLock = NSLock()
    private var stopped = false
    private var errorBytes = Data()
    private var nextID: UInt32 = 0
    private var extensions = Set<String>()
    public var timeout: Int32 = 90_000

    public init(host: String, proxyPath: String = "", askpass: String? = nil) throws {
        guard !host.isEmpty, !host.hasPrefix("-"), !host.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "\0" }) else {
            throw SFTPError("请输入有效的 SSH 主机别名")
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-T", "-o", "ConnectTimeout=20", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "-o", "NumberOfPasswordPrompts=3", "-s", host, "sftp"]
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [proxyPath, home + "/miniconda3/bin", home + "/anaconda3/bin", home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "", "/usr/bin:/bin:/usr/sbin:/sbin"]
        environment["PATH"] = candidates.filter { !$0.isEmpty }.joined(separator: ":")
        if let askpass {
            environment["SSH_ASKPASS"] = askpass
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = environment["DISPLAY"] ?? ":0"
        }
        process.environment = environment
        try launch()
    }

    /// Used by integration tests against the system's real SFTP server.
    public init(serverExecutable: URL, arguments: [String]) throws {
        process.executableURL = serverExecutable; process.arguments = arguments
        try launch()
    }

    private func launch() throws {
        signal(SIGPIPE, SIG_IGN)
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.stateLock.lock()
            self.errorBytes.append(data)
            if self.errorBytes.count > 32768 { self.errorBytes.removeFirst(self.errorBytes.count - 32768) }
            self.stateLock.unlock()
        }
        do { try process.run() } catch { errors.fileHandleForReading.readabilityHandler = nil; throw error }
        // Close the parent's copies of the child-only pipe ends so EOF is observable.
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
    }

    deinit { stop() }

    public func stop() {
        stateLock.lock()
        if stopped { stateLock.unlock(); return }
        stopped = true
        stateLock.unlock()
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        try? input.fileHandleForWriting.close()
        // The child closing stdout wakes poll/read. Do not close an FD in use by another thread.
    }

    public func perform<T>(_ operation: @escaping (SFTPSession) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try operation(self)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    public var diagnostic: String {
        stateLock.lock(); defer { stateLock.unlock() }
        return String(decoding: errorBytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connectionError(_ detail: String) -> SFTPError {
        let log = diagnostic
        let error = SFTPError(log.isEmpty ? detail : "\(detail)\n\n\(log)")
        stop()
        return error
    }

    private func readExact(_ count: Int) throws -> Data {
        var data = Data()
        let fd = output.fileHandleForReading.fileDescriptor
        let deadline = Date().addingTimeInterval(Double(timeout) / 1000)
        while data.count < count {
            stateLock.lock(); let cancelled = stopped; stateLock.unlock()
            if cancelled { throw SFTPError("连接已关闭") }
            let remaining = Int32(max(0, deadline.timeIntervalSinceNow * 1000))
            guard remaining > 0 else { throw connectionError("等待 SFTP 响应超时") }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, min(remaining, 500))
            if ready == 0 { continue }
            if ready < 0 { if errno == EINTR { continue }; throw connectionError("无法读取 SSH 通道") }
            let bytes = try output.fileHandleForReading.read(upToCount: count - data.count) ?? Data()
            if bytes.isEmpty { throw connectionError("SSH 通道已关闭。请检查登录状态及远端 SFTP 子系统。") }
            data.append(bytes)
        }
        return data
    }

    private func send(_ packet: Packet) throws {
        var framed = Packet(); framed.put(UInt32(packet.bytes.count)); framed.bytes.append(packet.bytes)
        do { try input.fileHandleForWriting.write(contentsOf: framed.bytes) }
        catch { throw connectionError("无法写入 SSH 通道：\(error.localizedDescription)") }
    }

    private func receive() throws -> Packet {
        var length = Packet(try readExact(4)); let count = try length.u32()
        guard count > 0, count <= 16 * 1024 * 1024 else { throw connectionError("无效的 SFTP 数据包；代理程序可能向标准输出写入了日志") }
        return Packet(try readExact(Int(count)))
    }

    public func handshake() throws {
        var packet = Packet(); packet.put(UInt8(1)); packet.put(UInt32(3)); try send(packet)
        var response = try receive()
        guard try response.byte() == 2, try response.u32() == 3 else { throw SFTPError("远端不支持 SFTP v3") }
        while response.offset < response.bytes.count { extensions.insert(try response.string()); _ = try response.string() }
    }

    private func sendRequest(_ type: UInt8, _ body: (inout Packet) -> Void) throws -> UInt32 {
        nextID &+= 1
        var packet = Packet(); packet.put(type); packet.put(nextID); body(&packet); try send(packet)
        return nextID
    }

    private func response() throws -> (UInt8, UInt32, Packet) {
        var packet = try receive(); let type = try packet.byte(), id = try packet.u32()
        return (type, id, packet)
    }

    private func request(_ type: UInt8, expecting: UInt8, _ body: (inout Packet) -> Void) throws -> Packet {
        let id = try sendRequest(type, body)
        let (kind, responseID, packet) = try response()
        guard responseID == id else { throw SFTPError("SFTP 响应序号不匹配") }
        if kind == 101 { try checkStatus(packet) }
        guard kind == expecting else { throw SFTPError("意外的 SFTP 响应类型：\(kind)") }
        return packet
    }

    private func checkStatus(_ packet: Packet) throws {
        var packet = packet; let code = try packet.u32(); let message = try packet.string()
        if code != 0 { throw SFTPError(message.isEmpty ? "SFTP 错误 \(code)" : message, code: code) }
    }

    public func realpath(_ path: String) throws -> String {
        var packet = try request(16, expecting: 104) { $0.put(path) }
        guard try packet.u32() > 0 else { throw SFTPError("无法解析远程目录") }
        return try packet.string()
    }

    public func stat(_ path: String, followLink: Bool = true) throws -> FileEntry {
        var packet = try request(followLink ? 17 : 7, expecting: 105) { $0.put(path) }
        return try packet.attrs(name: (path as NSString).lastPathComponent, path: path)
    }

    public func exists(_ path: String) throws -> Bool {
        do { _ = try stat(path, followLink: false); return true }
        catch let error as SFTPError where error.code == 2 { return false }
    }

    public func list(_ path: String, cancellation: Cancellation? = nil) throws -> [FileEntry] {
        try cancellation?.check()
        var opened = try request(11, expecting: 102) { $0.put(path) }
        let handle = try opened.data()
        defer { try? close(handle) }
        var entries: [FileEntry] = []
        while true {
            try cancellation?.check()
            do {
                var packet = try request(12, expecting: 104) { $0.put(handle) }
                let count = try packet.u32()
                guard count < 1_000_000 else { throw SFTPError("目录条目数量异常") }
                for _ in 0..<count {
                    let name = try packet.string(); _ = try packet.data() // longname is not parsed.
                    let entry = try packet.attrs(name: name, path: RemotePath.join(path, name))
                    if name == "." || name == ".." { continue }
                    guard RemotePath.safeName(name) else { throw SFTPError("远端返回了不安全的文件名") }
                    entries.append(entry)
                }
            } catch let error as SFTPError where error.code == 1 { break }
        }
        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private func close(_ handle: Data) throws { _ = try request(4, expecting: 101) { $0.put(handle) } }

    public func mkdir(_ path: String) throws { _ = try request(14, expecting: 101) { $0.put(path); $0.put(UInt32(4)); $0.put(UInt32(0o755)) } }
    public func remove(_ path: String) throws { _ = try request(13, expecting: 101) { $0.put(path) } }
    public func rmdir(_ path: String) throws { _ = try request(15, expecting: 101) { $0.put(path) } }
    public func rename(_ from: String, to: String) throws { _ = try request(18, expecting: 101) { $0.put(from); $0.put(to) } }

    public func uniquePath(_ path: String) throws -> String {
        if try !exists(path) { return path }
        let parent = RemotePath.parent(path), name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        for index in 2...10000 {
            let candidate = RemotePath.join(parent, "\(stem) (\(index))" + (ext.isEmpty ? "" : ".\(ext)"))
            if try !exists(candidate) { return candidate }
        }
        throw SFTPError("同名文件过多，请选择其他名称")
    }

    public typealias Progress = (UInt64, UInt64) -> Void

    /// Scan once before writing so every callback describes the entire queued item.
    @discardableResult
    public func upload(_ local: URL, to requestedPath: String, cancellation: Cancellation, progress: Progress, destinationResolved: ((String) -> Void)? = nil) throws -> String {
        let plan = try TransferPlan.local(local, cancellation: cancellation)
        try cancellation.check()
        let path = try uniquePath(requestedPath)
        destinationResolved?(path)
        var completed: UInt64 = 0
        progress(0, plan.bytes)
        try upload(plan, to: path, completed: &completed, total: plan.bytes, cancellation: cancellation, progress: progress)
        progress(completed, plan.bytes)
        return path
    }

    private func upload(_ plan: TransferPlan, to path: String, completed: inout UInt64, total: UInt64, cancellation: Cancellation, progress: Progress) throws {
        try cancellation.check()
        let local = URL(fileURLWithPath: plan.path)
        if let children = plan.children {
            try mkdir(path)
            for child in children {
                try upload(child, to: RemotePath.join(path, child.name), completed: &completed, total: total, cancellation: cancellation, progress: progress)
            }
            return
        }
        let values = try local.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true,
              UInt64(max(0, values.fileSize ?? 0)) == plan.bytes else {
            throw SFTPError("文件在统计后发生变化，请重新传输：\(plan.name)")
        }
        let temporary = RemotePath.join(RemotePath.parent(path), ".senda-\(UUID().uuidString).part")
        var opened = try request(3, expecting: 102) { $0.put(temporary); $0.put(UInt32(2 | 8 | 32)); $0.put(UInt32(4)); $0.put(UInt32(0o600)) }
        let handle = try opened.data()
        var closed = false, committed = false
        defer {
            if !closed { try? close(handle) }
            if !committed { try? remove(temporary) }
        }
        let file = try FileHandle(forReadingFrom: local)
        defer { try? file.close() }
        var offset: UInt64 = 0, acknowledged: UInt64 = 0
        while true {
            try cancellation.check()
            var pending: [UInt32: UInt64] = [:]
            for _ in 0..<16 {
                guard let data = try file.read(upToCount: 32768), !data.isEmpty else { break }
                let position = offset
                let id = try sendRequest(6) { $0.put(handle); $0.put(position); $0.put(data) }
                pending[id] = UInt64(data.count); offset += UInt64(data.count)
            }
            if pending.isEmpty { break }
            // Drain the full window even after an error so the protocol remains synchronized.
            var firstError: Error?
            for _ in 0..<pending.count {
                let (type, id, packet) = try response()
                guard type == 101, let count = pending.removeValue(forKey: id) else { throw SFTPError("上传响应无效") }
                do { try checkStatus(packet); acknowledged += count } catch { if firstError == nil { firstError = error } }
            }
            if let error = firstError { throw error }
            guard acknowledged <= plan.bytes else { throw SFTPError("文件在传输过程中变大：\(plan.name)") }
            progress(completed + acknowledged, total)
        }
        try cancellation.check()
        guard acknowledged == plan.bytes else { throw SFTPError("文件在传输过程中变小：\(plan.name)") }
        try close(handle); closed = true
        // Set final permissions only after transfer; partial files remain private.
        let mode = try FileManager.default.attributesOfItem(atPath: local.path)[.posixPermissions] as? NSNumber
        _ = try request(9, expecting: 101) { $0.put(temporary); $0.put(UInt32(4)); $0.put(mode?.uint32Value ?? 0o644) }
        try rename(temporary, to: path); committed = true
        completed += plan.bytes
    }

    /// Downloads via private temporary files. Total includes all regular descendants.
    public func download(_ remote: String, to local: URL, cancellation: Cancellation, progress: Progress) throws {
        let plan = try downloadPlan(remote, cancellation: cancellation)
        var completed: UInt64 = 0
        progress(0, plan.bytes)
        try download(plan, to: local, completed: &completed, total: plan.bytes, cancellation: cancellation, progress: progress)
        progress(completed, plan.bytes)
    }

    private func downloadPlan(_ path: String, entry: FileEntry? = nil, cancellation: Cancellation) throws -> TransferPlan {
        try cancellation.check()
        let attrs = try entry ?? stat(path, followLink: false)
        guard !attrs.isSymbolicLink else { throw SFTPError("暂不传输符号链接：\(attrs.name)") }
        if attrs.isDirectory {
            let children = try list(path, cancellation: cancellation).filter { !$0.isSymbolicLink }
                .map { try downloadPlan($0.path, entry: $0, cancellation: cancellation) }
            return try TransferPlan(path: path, children: children)
        }
        let fileType = attrs.permissions & 0o170000
        guard fileType == 0 || fileType == 0o100000 else { throw SFTPError("暂不传输特殊文件：\(attrs.name)") }
        return TransferPlan(path: path, bytes: attrs.size)
    }

    private func download(_ plan: TransferPlan, to local: URL, completed: inout UInt64, total: UInt64, cancellation: Cancellation, progress: Progress) throws {
        try cancellation.check()
        let remote = plan.path
        guard !FileManager.default.fileExists(atPath: local.path) else { throw SFTPError("目标已存在：\(local.lastPathComponent)") }
        if let children = plan.children {
            try FileManager.default.createDirectory(at: local, withIntermediateDirectories: false)
            for child in children {
                try download(child, to: local.appendingPathComponent(child.name), completed: &completed, total: total, cancellation: cancellation, progress: progress)
            }
            return
        }
        let attrs = try stat(remote, followLink: false)
        guard !attrs.isSymbolicLink, !attrs.isDirectory, attrs.size == plan.bytes else {
            throw SFTPError("文件在统计后发生变化，请重新传输：\(plan.name)")
        }
        let temporary = local.deletingLastPathComponent().appendingPathComponent(".senda-\(UUID().uuidString).part")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw SFTPError("无法创建下载文件") }
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: temporary) } }
        var opened = try request(3, expecting: 102) { $0.put(remote); $0.put(UInt32(1)); $0.put(UInt32(0)) }
        let handle = try opened.data()
        var closed = false
        defer { if !closed { try? close(handle) } }
        let file = try FileHandle(forWritingTo: temporary)
        defer { try? file.close() }
        var offset: UInt64 = 0
        // Pipeline reads over high latency proxies, retaining response IDs and offsets.
        while offset < attrs.size {
            try cancellation.check()
            var pending: [UInt32: (UInt64, UInt32)] = [:]
            var nextOffset = offset
            for _ in 0..<16 where nextOffset < attrs.size {
                let position = nextOffset, count = UInt32(min(32768, attrs.size - position))
                let id = try sendRequest(5) { $0.put(handle); $0.put(position); $0.put(count) }
                pending[id] = (position, count); nextOffset += UInt64(count)
            }
            var firstError: Error?
            var remainders: [(UInt64, UInt32)] = []
            for _ in 0..<pending.count {
                let (type, id, body) = try response()
                guard let (position, requested) = pending.removeValue(forKey: id) else { throw SFTPError("下载响应无效") }
                do {
                    if type == 101 { try checkStatus(body); throw SFTPError("远程文件在传输过程中发生变化") }
                    guard type == 103 else { throw SFTPError("下载响应无效") }
                    var body = body; let data = try body.data()
                    guard !data.isEmpty, data.count <= Int(requested) else { throw SFTPError("远程文件数据长度异常") }
                    try file.seek(toOffset: position); try file.write(contentsOf: data)
                    if data.count < Int(requested) { remainders.append((position + UInt64(data.count), requested - UInt32(data.count))) }
                } catch { if firstError == nil { firstError = error } }
            }
            if let error = firstError { throw error }
            // Drain pipelined replies before issuing sequential repairs for legal short reads.
            for (position, count) in remainders {
                var filled: UInt32 = 0
                while filled < count {
                    try cancellation.check()
                    var tail = try request(5, expecting: 103) { $0.put(handle); $0.put(position + UInt64(filled)); $0.put(count - filled) }
                    let bytes = try tail.data()
                    guard !bytes.isEmpty, bytes.count <= Int(count - filled) else { throw SFTPError("远程文件长度发生变化") }
                    try file.seek(toOffset: position + UInt64(filled)); try file.write(contentsOf: bytes)
                    filled += UInt32(bytes.count)
                }
            }
            offset = nextOffset; progress(completed + offset, total)
        }
        try cancellation.check()
        try close(handle); closed = true
        guard try stat(remote, followLink: false).size == plan.bytes else { throw SFTPError("远程文件在传输过程中发生变化：\(plan.name)") }
        try file.synchronize(); try file.close()
        try FileManager.default.setAttributes([.posixPermissions: attrs.permissions & 0o777], ofItemAtPath: temporary.path)
        try FileManager.default.moveItem(at: temporary, to: local)
        committed = true
        completed += plan.bytes
    }
}
