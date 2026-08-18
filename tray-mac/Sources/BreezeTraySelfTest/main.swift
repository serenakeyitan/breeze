import Foundation
import BreezeTrayCore

var failures = 0

func expect(_ cond: Bool, _ message: String) {
    if cond {
        print("OK  \(message)")
    } else {
        print("FAIL \(message)")
        failures += 1
    }
}

let inboxJSON = """
{
  "notifications": [
    {"id":"1","type":"PullRequest","repo":"tornado-doc/tdoc","title":"human","html_url":"https://github.com/tornado-doc/tdoc/pull/1","number":1,"breeze_status":"human"},
    {"id":"2","type":"PullRequest","repo":"tornado-doc/tdoc","title":"new","html_url":"https://github.com/tornado-doc/tdoc/pull/2","number":2,"breeze_status":"new"},
    {"id":"3","type":"PullRequest","repo":"tornado-doc/tdoc","title":"done","html_url":"https://github.com/tornado-doc/tdoc/pull/3","number":3,"breeze_status":"done"}
  ]
}
"""

do {
    let snapshot = try InboxParser.parse(json: inboxJSON)
    expect(snapshot.notifications.count == 3, "parses three notifications")
    expect(snapshot.humanItems.map(\.id) == ["1"], "only breeze_status=human is surfaced")
    expect(snapshot.humanItems.first?.number == 1, "human item number is 1")
} catch {
    expect(false, "inbox parse threw \(error)")
}

do {
    _ = try InboxParser.parse(json: "not-json")
    expect(false, "invalid JSON should throw")
} catch {
    expect(true, "invalid JSON throws")
}

do {
    _ = try InboxParser.parse(json: #"{"ok":true}"#)
    expect(false, "missing notifications should throw")
} catch InboxParseError.missingNotifications {
    expect(true, "missing notifications is missingNotifications")
} catch {
    expect(false, "missing notifications threw \(error)")
}

let yaml = """
repos:
  - tornado-doc/tdoc
http_port: 7888   # comment
"""
expect(DaemonPort.parseYAML(yaml) == 7888, "yaml http_port")
expect(DaemonPort.resolve(yaml: yaml, plistHTTPPort: nil) == 7888, "resolve prefers yaml")
expect(DaemonPort.resolve(yaml: yaml, plistHTTPPort: 9000) == 9000, "resolve prefers plist")
expect(DaemonPort.resolve(yaml: nil, plistHTTPPort: nil) == 7878, "resolve fallback 7878")
expect(DaemonPort.baseURL(port: 7888) == "http://127.0.0.1:7888", "base URL")

let args = [
    "/opt/breeze/breeze-runner",
    "run",
    "--allow-repo",
    "tornado-doc/tdoc,example/other",
    "--author-follow-repo",
    "serenakeyitan/tokentorrent",
    "--http-port",
    "7888",
]
let config = DaemonPlistParser.parseArguments(args)
expect(config.allowedRepos == ["tornado-doc/tdoc", "example/other"], "plist allow-repo csv")
expect(config.authorFollowRepos == ["serenakeyitan/tokentorrent"], "plist author-follow csv")
expect(config.httpPort == 7888, "plist http-port")
expect(config.executable?.hasSuffix("breeze-runner") == true, "plist executable")

let start = DaemonCommand.startArguments(allowedRepos: ["tornado-doc/tdoc"], httpPort: 7888)
expect(start == ["start", "--allow-repo", "tornado-doc/tdoc", "--http-port", "7888"], "start args")
let startFollow = DaemonCommand.startArguments(
    allowedRepos: ["tornado-doc/tdoc", "serenakeyitan/tokentorrent"],
    httpPort: 7888,
    authorFollowRepos: ["serenakeyitan/tokentorrent"]
)
expect(
    startFollow == [
        "start",
        "--allow-repo",
        "tornado-doc/tdoc,serenakeyitan/tokentorrent",
        "--author-follow-repo",
        "serenakeyitan/tokentorrent",
        "--http-port",
        "7888",
    ],
    "start args keep author-follow"
)
expect(!start.contains(where: { $0.contains("tree-repo") }), "no tree-repo flag")

let status = """
breeze-runner status
allowed repos: tornado-doc/tdoc
"""
expect(DaemonCommand.parseAllowedRepos(fromStatus: status) == ["tornado-doc/tdoc"], "status parser")

if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
print("ALL SELF-TESTS PASSED")
