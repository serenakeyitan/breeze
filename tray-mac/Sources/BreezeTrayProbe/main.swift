import Foundation
import BreezeTrayCore

@main
struct Probe {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            fputs("usage: breeze-tray-probe inbox|parse-plist|port|start-args [...]\n", stderr)
            exit(2)
        }
        switch command {
        case "inbox":
            let source = args.dropFirst().first ?? "-"
            let data: Data
            if source == "-" {
                data = FileHandle.standardInput.readDataToEndOfFile()
            } else if source.hasPrefix("http://") || source.hasPrefix("https://") {
                guard let url = URL(string: source) else { throw ExitError("bad url") }
                data = try Data(contentsOf: url)
            } else {
                data = try Data(contentsOf: URL(fileURLWithPath: source))
            }
            let snapshot = try InboxParser.parse(data: data)
            print("total=\(snapshot.notifications.count)")
            print("human=\(snapshot.humanItems.count)")
            for item in snapshot.humanItems {
                print("\(item.id)\t\(item.repo)\t#\(item.number)\t\(item.title)")
            }
        case "parse-plist":
            guard let path = args.dropFirst().first else { throw ExitError("parse-plist needs a file") }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let config = DaemonPlistParser.parsePlistData(data) else {
                throw ExitError("could not parse plist")
            }
            print("repos=\(config.allowedRepos.joined(separator: ","))")
            if let port = config.httpPort {
                print("http_port=\(port)")
            }
        case "port":
            let path = args.dropFirst().first
            let yaml = path.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            print(DaemonPort.resolve(yaml: yaml, plistHTTPPort: nil))
        case "start-args":
            let repos = Array(args.dropFirst())
            print(DaemonCommand.startArguments(allowedRepos: repos, httpPort: nil).joined(separator: " "))
        default:
            throw ExitError("unknown command \(command)")
        }
    }
}

struct ExitError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
