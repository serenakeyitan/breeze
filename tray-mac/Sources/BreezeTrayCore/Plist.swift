import Foundation

public struct DaemonPlistConfig: Equatable, Sendable {
    public let executable: String?
    public let allowedRepos: [String]
    public let authorFollowRepos: [String]
    public let httpPort: Int?

    public init(executable: String?, allowedRepos: [String], httpPort: Int?, authorFollowRepos: [String] = []) {
        self.executable = executable
        self.allowedRepos = allowedRepos
        self.authorFollowRepos = authorFollowRepos
        self.httpPort = httpPort
    }
}

public enum DaemonPlistParser {
    public static func parseArguments(_ args: [String]) -> DaemonPlistConfig {
        var allowedRepos: [String] = []
        var authorFollowRepos: [String] = []
        var httpPort: Int?
        var executable: String?
        if let first = args.first, first.hasSuffix("breeze-runner") || first.contains("breeze-runner") {
            executable = first
        }
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--allow-repo" || arg == "--allow-repos", i + 1 < args.count {
                allowedRepos = args[i + 1]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                i += 2
                continue
            }
            if arg == "--author-follow-repo" || arg == "--author-follow-repos", i + 1 < args.count {
                authorFollowRepos = args[i + 1]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                i += 2
                continue
            }
            if arg == "--http-port", i + 1 < args.count {
                httpPort = Int(args[i + 1])
                i += 2
                continue
            }
            i += 1
        }
        return DaemonPlistConfig(
            executable: executable,
            allowedRepos: allowedRepos,
            httpPort: httpPort,
            authorFollowRepos: authorFollowRepos
        )
    }

    public static func parsePlistData(_ data: Data) -> DaemonPlistConfig? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String]
        else {
            return nil
        }
        return parseArguments(args)
    }

    public static func findPlist(in directory: URL, fileManager: FileManager = .default) -> URL? {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }
        return entries
            .filter { $0.hasPrefix("com.breeze.runner.") && $0.hasSuffix(".plist") && !$0.hasSuffix(".bak") }
            .sorted()
            .first
            .map { directory.appendingPathComponent($0) }
    }
}

public enum DaemonCommand {
    public static func startArguments(allowedRepos: [String], httpPort: Int?, authorFollowRepos: [String] = []) -> [String] {
        var args = ["start", "--allow-repo", allowedRepos.joined(separator: ",")]
        if !authorFollowRepos.isEmpty {
            args.append(contentsOf: ["--author-follow-repo", authorFollowRepos.joined(separator: ",")])
        }
        if let httpPort {
            args.append(contentsOf: ["--http-port", String(httpPort)])
        }
        return args
    }

    public static let stopArguments = ["stop"]
    public static let statusArguments = ["status"]

    public static func parseAllowedRepos(fromStatus output: String) -> [String] {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("allowed repos:") {
                let value = trimmed.dropFirst("allowed repos:".count).trimmingCharacters(in: .whitespaces)
                if value == "all" || value.isEmpty {
                    return []
                }
                return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        return []
    }
}
