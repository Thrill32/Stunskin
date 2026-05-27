import SwiftUI

@main
struct StunskinApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        
        /*WindowGroup(id: "main") {
            ContentView()
        }*/

        WindowGroup { //keep app alive while making it launchable from the AppDelegate
            EmptyView()
        }.defaultSize(width: 0, height: 0)
        
        
    }
}

#Preview {
    ContentView()
}

