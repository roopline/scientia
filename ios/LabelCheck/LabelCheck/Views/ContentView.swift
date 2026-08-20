import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var master: ProductMasterStore
    @State private var selection = Tab.scan

    enum Tab: Hashable { case scan, master, history, settings }

    var body: some View {
        TabView(selection: $selection) {
            ScanView()
                .tabItem { Label("スキャン", systemImage: "viewfinder") }
                .tag(Tab.scan)

            MasterListView()
                .tabItem { Label("商品マスタ", systemImage: "list.bullet.rectangle") }
                .badge(master.products.isEmpty ? Text("!") : nil)
                .tag(Tab.master)

            HistoryView()
                .tabItem { Label("履歴", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ProductMasterStore())
        .environmentObject(HistoryStore())
        .environmentObject(AppSettings())
}
