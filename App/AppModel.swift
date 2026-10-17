import SwiftUI
import WidgetKit

enum Sheet: Identifiable {
    case add(voice: Bool)
    case edit(TodoItem)
    case settings
    case report(URL)

    var id: String {
        switch self {
        case .add(let voice): return "add-\(voice)"
        case .edit(let item): return "edit-\(item.id)"
        case .settings: return "settings"
        case .report(let url): return "report-\(url.lastPathComponent)"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tasks: [TodoItem] = []
    @Published var sheet: Sheet?

    init() {
        reload()
        Notifier.requestPermission()
    }

    func reload() {
        tasks = TaskStore.shared.load()
    }

    /// Handles taps coming from the widget (atodo://...).
    func handle(_ url: URL) {
        reload()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch url.host {
        case "add":
            sheet = .add(voice: query.first(where: { $0.name == "voice" })?.value == "1")
        case "edit":
            if let id = query.first(where: { $0.name == "id" })?.value, let item = tasks.first(where: { $0.id == id }) {
                sheet = .edit(item)
            }
        case "report":
            makeReport()
        default:
            sheet = nil
        }
    }

    func save(_ item: TodoItem, addToCalendar: Bool) async {
        TaskStore.shared.upsert(item)
        Notifier.schedule(item)
        if addToCalendar, let due = item.due {
            _ = await CalendarHelper.addEvent(title: item.title, start: due)
        }
        reload()
    }

    func toggle(_ item: TodoItem) {
        if let updated = TaskStore.shared.toggle(id: item.id) {
            if updated.done { Notifier.cancel(updated.id) } else { Notifier.schedule(updated) }
        }
        reload()
    }

    func delete(_ item: TodoItem) {
        Notifier.cancel(item.id)
        TaskStore.shared.delete(id: item.id)
        reload()
    }

    func clearFinished() {
        for item in tasks where item.done { TaskStore.shared.delete(id: item.id) }
        reload()
    }

    func makeReport() {
        sheet = .report(ReportBuilder.make(tasks))
    }
}
