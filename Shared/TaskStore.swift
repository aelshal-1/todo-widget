import Foundation
import WidgetKit

struct TodoItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var due: Date?
    var done: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date?
    var remind: Bool = true
}

/// Tasks live in one JSON file inside the shared app-group folder.
final class TaskStore {
    static let shared = TaskStore()

    private let url = AppGroup.containerURL.appendingPathComponent("tasks.json")
    private let lock = NSLock()

    func load() -> [TodoItem] {
        lock.lock(); defer { lock.unlock() }
        return read()
    }

    func upsert(_ item: TodoItem) {
        mutate { all in
            if let i = all.firstIndex(where: { $0.id == item.id }) { all[i] = item } else { all.append(item) }
        }
    }

    func delete(id: String) {
        mutate { all in all.removeAll { $0.id == id } }
    }

    @discardableResult
    func toggle(id: String) -> TodoItem? {
        var result: TodoItem?
        mutate { all in
            guard let i = all.firstIndex(where: { $0.id == id }) else { return }
            all[i].done.toggle()
            all[i].completedAt = all[i].done ? Date() : nil
            result = all[i]
        }
        return result
    }

    // MARK: - Ordering

    /// Open tasks first (overdue, then soonest due, then undated), then today's finished ones.
    static func ordered(_ items: [TodoItem], now: Date = Date()) -> [TodoItem] {
        let open = items.filter { !$0.done }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
        let doneToday = items.filter { $0.done && Calendar.current.isDate($0.completedAt ?? .distantPast, inSameDayAs: now) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return open + doneToday
    }

    // MARK: - File access

    private func mutate(_ change: (inout [TodoItem]) -> Void) {
        lock.lock()
        var all = read()
        change(&all)
        write(all)
        lock.unlock()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func read() -> [TodoItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([TodoItem].self, from: data)) ?? []
    }

    private func write(_ items: [TodoItem]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
