import SwiftUI

@main
struct DeskCallApp: App {
    @StateObject private var store = LookupStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            LookupView()
                .tabItem { Label("Lookup", systemImage: "magnifyingglass") }
            HistoryView()
                .tabItem { Label("Recent", systemImage: "clock.arrow.circlepath") }
            DirectoryView()
                .tabItem { Label("Caller ID", systemImage: "phone.badge.checkmark") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
