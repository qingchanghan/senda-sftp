import Foundation

/// Immutable snapshot of one transfer tree. A directory's bytes exclude symlinks.
struct TransferPlan {
    let path: String
    let bytes: UInt64
    let children: [TransferPlan]?
    var name: String { (path as NSString).lastPathComponent }

    init(path: String, bytes: UInt64) {
        self.path = path; self.bytes = bytes; children = nil
    }

    init(path: String, children: [TransferPlan]) throws {
        self.path = path; self.children = children
        bytes = try children.reduce(UInt64(0)) { sum, child in
            let (value, overflow) = sum.addingReportingOverflow(child.bytes)
            guard !overflow else { throw SFTPError("目录总大小超出支持范围") }
            return value
        }
    }

    static func local(_ url: URL, cancellation: Cancellation) throws -> TransferPlan {
        try cancellation.check()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isSymbolicLink != true else { throw SFTPError("暂不传输符号链接：\(url.lastPathComponent)") }
        if values.isDirectory == true {
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys))
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .filter { try $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true }
                .map { try local($0, cancellation: cancellation) }
            return try TransferPlan(path: url.path, children: children)
        }
        guard values.isRegularFile == true else { throw SFTPError("暂不传输特殊文件：\(url.lastPathComponent)") }
        return TransferPlan(path: url.path, bytes: UInt64(max(0, values.fileSize ?? 0)))
    }
}
