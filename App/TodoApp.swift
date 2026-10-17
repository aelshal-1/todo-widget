import SwiftUI

@main
struct TodoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { model.handle($0) }
        }
    }
}
