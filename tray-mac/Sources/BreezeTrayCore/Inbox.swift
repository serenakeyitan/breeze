import Foundation

public struct InboxNotification: Equatable, Sendable {
    public let id: String
    public let type: String
    public let repo: String
    public let title: String
    public let htmlURL: String
    public let number: Int
    public let breezeStatus: String

    public init(
        id: String,
        type: String,
        repo: String,
        title: String,
        htmlURL: String,
        number: Int,
        breezeStatus: String
    ) {
        self.id = id
        self.type = type
        self.repo = repo
        self.title = title
        self.htmlURL = htmlURL
        self.number = number
        self.breezeStatus = breezeStatus
    }
}

public struct InboxSnapshot: Equatable, Sendable {
    public let notifications: [InboxNotification]

    public init(notifications: [InboxNotification]) {
        self.notifications = notifications
    }

    public var humanItems: [InboxNotification] {
        notifications.filter { $0.breezeStatus == "human" }
    }
}

public enum InboxParseError: Error, Equatable {
    case invalidJSON
    case missingNotifications
}

public enum InboxParser {
    public static func parse(data: Data) throws -> InboxSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InboxParseError.invalidJSON
        }
        guard let rawItems = root["notifications"] as? [[String: Any]] else {
            throw InboxParseError.missingNotifications
        }
        let items = rawItems.compactMap { item -> InboxNotification? in
            guard
                let id = item["id"] as? String,
                let type = item["type"] as? String,
                let repo = item["repo"] as? String,
                let title = item["title"] as? String
            else {
                return nil
            }
            let htmlURL = (item["html_url"] as? String) ?? ""
            let number: Int
            if let value = item["number"] as? Int {
                number = value
            } else if let value = item["number"] as? Double {
                number = Int(value)
            } else {
                number = 0
            }
            let status = (item["breeze_status"] as? String) ?? "new"
            return InboxNotification(
                id: id,
                type: type,
                repo: repo,
                title: title,
                htmlURL: htmlURL,
                number: number,
                breezeStatus: status
            )
        }
        return InboxSnapshot(notifications: items)
    }

    public static func parse(json: String) throws -> InboxSnapshot {
        guard let data = json.data(using: .utf8) else {
            throw InboxParseError.invalidJSON
        }
        return try parse(data: data)
    }
}
