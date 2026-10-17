import AppIntents
import SwiftUI
import WidgetKit

@main
struct TodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodoWidget()
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoWidget", provider: Provider()) { entry in
            TodoWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("Todo")
        .description("Your tasks. Tick them off, add by voice.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct TodoEntry: TimelineEntry {
    let date: Date
    let tasks: [TodoItem]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: Date(), tasks: Samples.tasks)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        let tasks = TaskStore.shared.load()
        completion(TodoEntry(date: Date(), tasks: context.isPreview && tasks.isEmpty ? Samples.tasks : tasks))
    }

    /// One entry now, plus one at every moment a chip changes color
    /// (24 h before, 2 h before, at due time) and at midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        let tasks = TaskStore.shared.load()
        let now = Date()
        var moments: Set<Date> = [now]
        for task in tasks where !task.done {
            guard let due = task.due else { continue }
            for offset in [-24.0 * 3600, -2.0 * 3600, 0] {
                let moment = due.addingTimeInterval(offset)
                if moment > now { moments.insert(moment) }
            }
        }
        let cal = Calendar.current
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            moments.insert(midnight)
        }
        let entries = moments.sorted().prefix(40).map { TodoEntry(date: $0, tasks: tasks) }
        completion(Timeline(entries: Array(entries), policy: .atEnd))
    }
}

enum Samples {
    static var tasks: [TodoItem] {
        let now = Date()
        return [
            TodoItem(title: "Reply to the bank about UAT", due: now.addingTimeInterval(45 * 60)),
            TodoItem(title: "اشتري حليب وعيش"),
            TodoItem(title: "Dentist appointment", due: now.addingTimeInterval(26 * 3600)),
        ]
    }
}

enum Links {
    static let voice = URL(string: "atodo://add?voice=1")!
    static let add = URL(string: "atodo://add")!
    static let report = URL(string: "atodo://report")!
    static let open = URL(string: "atodo://open")!
    static func edit(_ id: String) -> URL { URL(string: "atodo://edit?id=\(id)")! }
}

// MARK: - Views

struct TodoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodoEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(entry: entry)
        case .systemMedium:
            ListView(entry: entry, maxRows: 2, showFooter: false)
        default:
            ListView(entry: entry, maxRows: 6, showFooter: true)
        }
    }
}

private func summary(_ tasks: [TodoItem], now: Date) -> String {
    let open = tasks.filter { !$0.done }
    let hot = open.filter { DueLevel.of($0.due, now: now).isHot }.count
    if open.isEmpty { return "All clear" }
    return hot > 0 ? "\(open.count) open · \(hot) due soon" : "\(open.count) open"
}

struct RoundIcon: View {
    let symbol: String
    let filled: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(filled ? Color.white : Theme.primary)
            .frame(width: 36, height: 36)
            .background(Circle().fill(filled ? Theme.accent : Theme.field))
    }
}

struct ListView: View {
    let entry: TodoEntry
    let maxRows: Int
    let showFooter: Bool

    var body: some View {
        let ordered = TaskStore.ordered(entry.tasks, now: entry.date)
        let rows = Array(ordered.prefix(maxRows))
        let extra = max(0, entry.tasks.filter { !$0.done }.count - rows.filter { !$0.done }.count)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Today")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.primary)
                    Text(summary(entry.tasks, now: entry.date))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                Link(destination: Links.voice) { RoundIcon(symbol: "mic.fill", filled: true) }
                Link(destination: Links.add) { RoundIcon(symbol: "plus", filled: false) }
            }

            if rows.isEmpty {
                Spacer(minLength: 0)
                Text("No tasks. Tap + or the mic.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(rows) { item in
                    WidgetRow(item: item, now: entry.date)
                }
                Spacer(minLength: 0)
            }

            if showFooter {
                HStack {
                    Link(destination: Links.report) {
                        Label("Report", systemImage: "doc.text")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                    Spacer()
                    if extra > 0 {
                        Link(destination: Links.open) {
                            Text("+\(extra) more")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct WidgetRow: View {
    let item: TodoItem
    let now: Date

    var body: some View {
        let level = item.done ? DueLevel.none : DueLevel.of(item.due, now: now)
        HStack(spacing: 6) {
            Button(intent: ToggleTaskIntent(taskID: item.id)) {
                CheckCircle(done: item.done, hot: level.isHot)
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Link(destination: Links.edit(item.id)) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Theme.secondary : Theme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let due = item.due, !item.done {
                DueChip(due: due, now: now)
            }
        }
        .frame(height: 38)
        .padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 10).fill(level.rowTint))
    }
}

struct SmallView: View {
    let entry: TodoEntry

    var body: some View {
        let open = TaskStore.ordered(entry.tasks, now: entry.date).filter { !$0.done }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(open.count)")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.primary)
                    Text("open")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                RoundIcon(symbol: "mic.fill", filled: true)
            }
            Spacer(minLength: 0)
            if let next = open.first {
                Text("NEXT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondary)
                Text(next.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(2)
                if let due = next.due {
                    DueChip(due: due, now: entry.date)
                }
            } else {
                Text("All clear")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .widgetURL(Links.voice)
    }
}
