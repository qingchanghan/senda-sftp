import Foundation

/// A committed directory or an explicitly addressed file. Transfer destinations
/// always use directoryPath, even while the pane is displaying a single file.
public struct BrowserLocation: Sendable {
    public let directoryPath: String
    public let entries: [FileEntry]
    public let file: FileEntry?

    public init(directoryPath: String, entries: [FileEntry], file: FileEntry? = nil) {
        self.directoryPath = directoryPath; self.entries = entries; self.file = file
    }

    public static func local(_ requested: String, relativeTo directory: String) throws -> BrowserLocation {
        guard !requested.isEmpty, !requested.contains("\0") else { throw SFTPError("请输入文件或文件夹路径") }
        let url: URL
        if requested.lowercased().hasPrefix("file:") {
            guard let parsed = URL(string: requested), parsed.isFileURL,
                  parsed.host == nil || parsed.host == "" || parsed.host == "localhost",
                  parsed.query == nil, parsed.fragment == nil else { throw SFTPError("请输入本机的 file:// 地址") }
            url = parsed.standardizedFileURL
        } else {
            let path = (requested as NSString).expandingTildeInPath
            url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: directory, isDirectory: true)).standardizedFileURL
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let values = try url.resourceValues(forKeys: keys)
        if values.isSymbolicLink == true {
            let resolved = url.resolvingSymlinksInPath()
            guard try resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw SFTPError("暂不传输符号链接：\(url.lastPathComponent)")
            }
            return try local(resolved.path, relativeTo: directory)
        }
        func entry(_ item: URL, _ value: URLResourceValues) -> FileEntry {
            let mode: UInt32 = value.isSymbolicLink == true ? 0o120000 :
                (value.isDirectory == true ? 0o040000 : (value.isRegularFile == true ? 0o100000 : 0))
            return FileEntry(name: item.lastPathComponent, path: item.path,
                             size: UInt64(max(0, value.fileSize ?? 0)), permissions: mode,
                             modified: value.contentModificationDate)
        }
        if values.isDirectory == true {
            let entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys))
                .map { try entry($0, $0.resourceValues(forKeys: keys)) }
                .sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            return BrowserLocation(directoryPath: url.path, entries: entries)
        }
        guard values.isRegularFile == true else { throw SFTPError("暂不传输特殊文件：\(url.lastPathComponent)") }
        let file = entry(url, values)
        return BrowserLocation(directoryPath: url.deletingLastPathComponent().path, entries: [file], file: file)
    }
}

extension SFTPSession {
    /// Run on the session queue, like list/stat. File resolution never lists the parent.
    public func location(at requested: String, relativeTo directory: String, cancellation: Cancellation) throws -> BrowserLocation {
        try cancellation.check()
        guard !requested.isEmpty, !requested.contains("\0") else { throw SFTPError("请输入文件或文件夹路径") }
        let address: String
        if requested == "~" || requested.hasPrefix("~/") {
            let home = try realpath(".")
            address = requested == "~" ? home : RemotePath.join(home, String(requested.dropFirst(2)))
        } else {
            address = requested.hasPrefix("/") ? requested : RemotePath.join(directory.isEmpty ? "." : directory, requested)
        }
        try cancellation.check()
        let attributes = try stat(address, followLink: false)
        let isDirectory: Bool
        if attributes.isSymbolicLink {
            isDirectory = try stat(address).isDirectory
            guard isDirectory else { throw SFTPError("暂不传输符号链接：\(attributes.name)") }
        } else { isDirectory = attributes.isDirectory }
        guard isDirectory || attributes.isRegularFile else { throw SFTPError("暂不传输特殊文件：\(attributes.name)") }
        try cancellation.check()
        let path = try realpath(address)
        try cancellation.check()
        if isDirectory {
            return BrowserLocation(directoryPath: path, entries: try list(path, cancellation: cancellation))
        }
        let file = FileEntry(name: (path as NSString).lastPathComponent, path: path,
                             size: attributes.size, permissions: attributes.permissions, modified: attributes.modified)
        return BrowserLocation(directoryPath: RemotePath.parent(path), entries: [file], file: file)
    }
}
