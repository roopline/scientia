import SwiftUI

@main
struct LabelCheckApp: App {
    @StateObject private var master = ProductMasterStore()
    @StateObject private var history = HistoryStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(master)
                .environmentObject(history)
                .environmentObject(settings)
        }
    }
}
