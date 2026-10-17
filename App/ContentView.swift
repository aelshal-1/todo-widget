import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                list(now: context.date)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.sheet = .settings } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.makeReport() } label: { Image(systemName: "doc.text") }
                        .accessibilityLabel("Make a report file")
                }
            }
            .safeAreaInset(edge: .bottom) { addBar }
        }
        .tint(Theme.accent)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .add(let voice):
                QuickAddView(existing: nil, startWithVoice: voice)
            case .edit(let item):
                QuickAddView(existing: item, startWithVoice: false)
            case .settings:
                SettingsView()
            case .report(let url):
                ShareSheet(url: url)
            }
        }
    }

    private func list(now: Date) -> some View {
        let ordered = TaskStore.ordered(model.tasks, now: now)
        let open = ordered.filter { !$0.done }
        let done = model.tasks.filter { $0.done }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        return List {
            if open.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.secondary)
                        Text("All clear")
                            .font(.headline)
                        Text("Tap the mic and say a task in Arabic or English.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section("Open · \(open.count)") {
                    ForEach(open) { item in row(item, now: now) }
                }
            }
            if !done.isEmpty {
                Section {
                    ForEach(done) { item in row(item, now: now) }
                } header: {
                    HStack {
                        Text("Done")
                        Spacer()
                        Button("Clear") { model.clearFinished() }
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private func row(_ item: TodoItem, now: Date) -> some View {
        let level = item.done ? DueLevel.none : DueLevel.of(item.due, now: now)
        return HStack(spacing: 12) {
            Button { model.toggle(item) } label: {
                CheckCircle(done: item.done, hot: level.isHot)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "Mark not done" : "Mark done")

            Button { model.sheet = .edit(item) } label: {
                HStack {
                    Text(item.title)
                        .font(.system(size: 16, weight: .medium))
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? Theme.secondary : Theme.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let due = item.due, !item.done {
                        DueChip(due: due, now: now)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(level.isHot ? level.rowTint : nil)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { model.delete(item) } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { model.toggle(item) } label: { Label(item.done ? "Undo" : "Done", systemImage: "checkmark") }
                .tint(Theme.accent)
        }
    }

    private var addBar: some View {
        HStack(spacing: 12) {
            Button { model.sheet = .add(voice: false) } label: {
                HStack {
                    Text("Type a task…")
                    Spacer()
                    Text("اكتب مهمة").environment(\.layoutDirection, .rightToLeft)
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.field))
            }
            .buttonStyle(.plain)

            Button { model.sheet = .add(voice: true) } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.accent))
            }
            .accessibilityLabel("Add a task by voice")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
