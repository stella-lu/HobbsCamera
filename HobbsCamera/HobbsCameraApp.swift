import SwiftUI
import SwiftData

@main
struct HobbsCameraApp: App {
    /// SwiftData container for `PhotoRecord`.
    /// This persists locally on-device in the app sandbox.
    private let container: ModelContainer = {
        let schema = Schema([PhotoRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
