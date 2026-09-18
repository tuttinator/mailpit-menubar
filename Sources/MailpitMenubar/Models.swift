import Foundation

struct MailAddress: Decodable, Sendable {
    let name: String
    let address: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case address = "Address"
    }

    /// "Alice <alice@example.com>" style label, falling back to the bare address.
    var display: String {
        name.isEmpty ? address : name
    }
}

struct MailpitMessage: Decodable, Sendable {
    let id: String
    let read: Bool
    let from: MailAddress?
    let to: [MailAddress]?
    let subject: String
    let created: String
    let snippet: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case read = "Read"
        case from = "From"
        case to = "To"
        case subject = "Subject"
        case created = "Created"
        case snippet = "Snippet"
    }

    var fromDisplay: String { from?.display ?? "Unknown sender" }
    var subjectDisplay: String { subject.isEmpty ? "(no subject)" : subject }
}

struct MessagesResponse: Decodable, Sendable {
    let total: Int
    let unread: Int
    let messages: [MailpitMessage]
}

struct MailpitStats: Decodable, Sendable {
    let total: Int
    let unread: Int

    enum CodingKeys: String, CodingKey {
        case total = "Total"
        case unread = "Unread"
    }
}

/// Websocket events from `/api/events`: `{"Type": "...", "Data": {...}}`.
enum MailpitEvent: Sendable {
    case new(MailpitMessage)
    case stats(MailpitStats)
    case other(String)

    private struct Envelope: Decodable { let type: String; enum CodingKeys: String, CodingKey { case type = "Type" } }
    private struct Payload<T: Decodable>: Decodable { let data: T; enum CodingKeys: String, CodingKey { case data = "Data" } }

    static func decode(_ data: Data) throws -> MailpitEvent {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(Envelope.self, from: data)
        switch envelope.type {
        case "new":
            return .new(try decoder.decode(Payload<MailpitMessage>.self, from: data).data)
        case "stats":
            return .stats(try decoder.decode(Payload<MailpitStats>.self, from: data).data)
        default:
            return .other(envelope.type)
        }
    }
}
