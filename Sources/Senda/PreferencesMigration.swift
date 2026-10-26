import Foundation

enum PreferencesMigration {
    /// Import only app-owned keys once; never change the old application's domain.
    static func run(into defaults: UserDefaults = .standard, legacy: [String: Any]? = nil) {
        guard !defaults.bool(forKey: "migratedFromHarbor") else { return }
        let old = legacy ?? defaults.persistentDomain(forName: "app.harbor.sftp") ?? [:]
        for (key, value) in old where ["lastHost", "localPath", "showHidden", "proxyPath"].contains(key) || key.hasPrefix("remotePath.") {
            if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "migratedFromHarbor")
    }
}
