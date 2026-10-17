import AppIntents
import Foundation

/// Runs when the checkbox on the widget is tapped — no app launch.
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle task"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        if let item = TaskStore.shared.toggle(id: taskID) {
            if item.done { Notifier.cancel(item.id) } else { Notifier.schedule(item) }
        }
        return .result()
    }
}
