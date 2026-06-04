import SwiftUI

struct ContentView: View {
    @StateObject var bm = BaseViewModel.shared
    
    var body: some View {
        TabView() {
            HomeView(pbm: bm) .tabItem {
                Label("Home", systemImage: "square")
            }
            SettingsView(pbm: bm) .tabItem {
                Label("Settings", systemImage: "square")
            }
        }
    }
}

//#Preview {
//    ContentView()
//}
