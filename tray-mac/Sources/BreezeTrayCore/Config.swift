import Foundation

public enum BreezePaths {
    public static func homeDirectory(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment["BREEZE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".breeze")
    }

    public static func configFile(fileManager: FileManager = .default) -> URL {
        homeDirectory(fileManager: fileManager).appendingPathComponent("config.yaml")
    }

    public static func launchdDirectory(fileManager: FileManager = .default) -> URL {
        homeDirectory(fileManager: fileManager)
            .appendingPathComponent("runner")
            .appendingPathComponent("launchd")
    }

    public static func logsDirectory(fileManager: FileManager = .default) -> URL {
        homeDirectory(fileManager: fileManager)
            .appendingPathComponent("runner")
            .appendingPathComponent("logs")
    }

    public static func trayStateFile(fileManager: FileManager = .default) -> URL {
        homeDirectory(fileManager: fileManager).appendingPathComponent("tray-state.json")
    }

    public static func traySeenFile(fileManager: FileManager = .default) -> URL {
        homeDirectory(fileManager: fileManager).appendingPathComponent("tray-seen.json")
    }

    public static func trayInstallDirectory(fileManager: FileManager = .default) -> URL {
        homeDirectory(fileManager: fileManager).appendingPathComponent("tray")
    }
}

public enum DaemonPort {
    public static let fallback = 7878

    public static func parseYAML(_ raw: String) -> Int? {
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("http_port:") {
                let value = trimmed.dropFirst("http_port:".count)
                    .split(separator: "#").first.map(String.init) ?? ""
                if let port = Int(value.trimmingCharacters(in: .whitespaces)),
                   port > 0, port < 65_536 {
                    return port
                }
            }
        }
        return nil
    }

    public static func resolve(
        yaml: String? = nil,
        plistHTTPPort: Int? = nil,
        defaultPort: Int = DaemonPort.fallback
    ) -> Int {
        if let plistHTTPPort {
            return plistHTTPPort
        }
        if let yaml, let parsed = parseYAML(yaml) {
            return parsed
        }
        return defaultPort
    }

    public static func baseURL(port: Int) -> String {
        "http://127.0.0.1:\(port)"
    }
}
