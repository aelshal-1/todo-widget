import EventKit
import Foundation
import Security

// MARK: - Settings

enum AppSettings {
    static let defaultModel = "claude-haiku-5-5"

    static var apiKey: String {
        get { Keychain.get("anthropic_api_key") ?? "" }
        set { Keychain.set(newValue, for: "anthropic_api_key") }
    }

    static var model: String {
        get {
            let value = UserDefaults.standard.string(forKey: "model") ?? ""
            return value.isEmpty ? defaultModel : value
        }
        set { UserDefaults.standard.set(newValue, forKey: "model") }
    }
}

enum Keychain {
    static func set(_ value: String, for key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Claude

struct ParsedTask {
    var title: String
    var due: Date?
    var isAppointment: Bool
}

enum ClaudeError: LocalizedError {
    case noKey
    case server(String)
    case badReply

    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your Claude API key in Settings first."
        case .server(let message): return message
        case .badReply: return "Couldn't understand Claude's reply. The text was kept as is."
        }
    }
}

enum ClaudeClient {
    static func parse(_ text: String) async throws -> ParsedTask {
        let key = AppSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ClaudeError.noKey }

        let now = DueText.format(Date(), "yyyy-MM-dd HH:mm, EEEE")
        let system = """
        You turn a to-do written or spoken in Egyptian Arabic, Arabic or English into JSON.
        Now is \(now), time zone \(TimeZone.current.identifier).
        Reply with ONLY one JSON object, no markdown, no explanation:
        {"title": "...", "due": "...", "calendar": false}
        Rules:
        - title: a short task title in the same language the user used, without the date or time words.
        - due: "yyyy-MM-dd HH:mm" when the user mentions a day or a time, otherwise an empty string "".
        - A day without a time means 09:00. A time without a day means its next occurrence.
        - calendar: true only for appointments or meetings (doctor, meeting, call, visit at a set time), otherwise false.
        """

        let body: [String: Any] = [
            "model": AppSettings.model,
            "max_tokens": 500,
            "system": system,
            "messages": [["role": "user", "content": text]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw ClaudeError.server(message ?? "Claude returned error \(http.statusCode).")
        }

        // The reply can contain a thinking block first; use the last text block.
        let blocks = json?["content"] as? [[String: Any]] ?? []
        guard let reply = blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let start = reply.firstIndex(of: "{"),
              let end = reply.lastIndex(of: "}"),
              let objectData = String(reply[start...end]).data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: objectData)) as? [String: Any]
        else { throw ClaudeError.badReply }

        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dueText = (object["due"] as? String) ?? ""
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let due = formatter.date(from: dueText.trimmingCharacters(in: .whitespaces))

        var appointment = false
        if let flag = object["calendar"] as? Bool { appointment = flag }
        if let flag = object["calendar"] as? String { appointment = ["true", "yes"].contains(flag.lowercased()) }

        return ParsedTask(title: title.isEmpty ? text : title, due: due, isAppointment: appointment && due != nil)
    }
}

// MARK: - Calendar

enum CalendarHelper {
    private static let store = EKEventStore()

    static func addEvent(title: String, start: Date) async -> Bool {
        do {
            guard try await store.requestWriteOnlyAccessToEvents() else { return false }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = start
            event.endDate = start.addingTimeInterval(3600)
            event.calendar = store.defaultCalendarForNewEvents
            event.addAlarm(EKAlarm(relativeOffset: -30 * 60))
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }
}
