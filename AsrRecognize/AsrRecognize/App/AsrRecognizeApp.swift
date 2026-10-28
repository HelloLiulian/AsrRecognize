import SwiftData
import SwiftUI

@main
struct AsrRecognizeApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(for: Meeting.self)
    }
}
