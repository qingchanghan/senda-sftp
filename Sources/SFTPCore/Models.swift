import Foundation
import Darwin

public struct FileEntry: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let size: UInt64
    public let permissions: UInt32
    public let modified: Date?
    public var isDirectory: Bool { permissions & 0o170000 == 0o040000 }
    public var isSymbolicLink: Bool { permissions & 0o170000 == 0o120000 }
    public init(name: String, path: String, size: UInt64 = 0, permissions: UInt32 = 0, modified: Date? = nil) {
        self.name = name; self.path = path; self.size = size
        self.permissions = permissions; self.modified = modified
    }
}

public struct SSHHost: Identifiable, Hashable, Sendable {
    public var id: String { alias }
    public let alias: String
    public let hostname: String
    public let user: String
    public let usesProxy: Bool
    public init(alias: String, hostname: String = "", user: String = "", usesProxy: Bool = false) {
        self.alias = alias; self.hostname = hostname; self.user = user; self.usesProxy = usesProxy
    }
}

public enum SSHConfig {
    public static func hosts(at url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")) -> [SSHHost] {
        var visited = Set<String>()
        let lines = expand(url, base: url.deletingLastPathComponent(), visited: &visited)
        return parse(lines.joined(separator: "\n"))
    }

    private static func expand(_ url: URL, base: URL, visited: inout Set<String>) -> [String] {
        guard visited.count < 64, visited.insert(url.standardizedFileURL.path).inserted,
              let source = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return source.components(separatedBy: .newlines).flatMap { line -> [String] in
            let words = tokens(line)
            guard words.first?.lowercased() == "include" else { return [line] }
            return words.dropFirst().flatMap { pattern -> [String] in
                let expanded = (pattern as NSString).expandingTildeInPath
                let absolute = expanded.hasPrefix("/") ? expanded : base.appendingPathComponent(expanded).path
                var result = glob_t()
                guard glob(absolute, 0, nil, &result) == 0 else { globfree(&result); return [] }
                defer { globfree(&result) }
                return (0..<Int(result.gl_pathc)).flatMap { index -> [String] in
                    guard let path = result.gl_pathv[index] else { return [] }
                    return expand(URL(fileURLWithPath: String(cString: path)), base: base, visited: &visited)
                }
            }
        }
    }

    // Parse only concrete aliases for discovery. OpenSSH remains the authority for resolution.
    public static func parse(_ source: String) -> [SSHHost] {
        var result: [SSHHost] = []
        var aliases: [String] = [], hostname = "", user = "", proxy = false
        func finish() {
            for alias in aliases where !result.contains(where: { $0.alias == alias }) {
                result.append(SSHHost(alias: alias, hostname: hostname, user: user, usesProxy: proxy))
            }
        }
        for line in source.components(separatedBy: .newlines) {
            let words = tokens(line)
            guard let first = words.first, words.count > 1 else { continue }
            let value = words.dropFirst().joined(separator: " ")
            switch first.lowercased() {
            case "host", "match":
                finish(); hostname = ""; user = ""; proxy = false
                aliases = first.lowercased() == "host" ? words.dropFirst().filter { !$0.contains(where: { "*?!".contains($0) }) } : []
            case "hostname": if hostname.isEmpty { hostname = value }
            case "user": if user.isEmpty { user = value }
            case "proxycommand", "proxyjump": proxy = proxy || value.lowercased() != "none"
            default: break
            }
        }
        finish()
        return result
    }

    static func tokens(_ line: String) -> [String] {
        var values: [String] = [], word = "", quote: Character?, escaped = false
        for char in line {
            if escaped { word.append(char); escaped = false; continue }
            if char == "\\" { escaped = true; continue }
            if let active = quote {
                if char == active { quote = nil } else { word.append(char) }
            } else if char == "\"" || char == "'" { quote = char
            } else if char == "#" { break
            } else if char.isWhitespace || (char == "=" && (values.isEmpty || (values.count == 1 && word.isEmpty))) {
                if !word.isEmpty { values.append(word); word = "" }
            } else { word.append(char) }
        }
        if !word.isEmpty { values.append(word) }
        return values
    }
}

public enum RemotePath {
    public static func join(_ parent: String, _ name: String) -> String {
        (parent == "/" ? "" : parent) + "/" + name
    }
    public static func parent(_ path: String) -> String {
        let result = (path as NSString).deletingLastPathComponent
        return result.isEmpty ? "/" : result
    }
    public static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}
