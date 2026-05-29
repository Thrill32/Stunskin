import SwiftUI

struct HomeView : View {
    
    @ObservedObject private var bm: BaseViewModel
    @ObservedObject public var dm: DaemonViewModel
    @State private var curCommand: String = ""
    init(pbm: BaseViewModel) {
        let bm = pbm
        _bm = ObservedObject(wrappedValue: bm)
        _dm = ObservedObject(wrappedValue: bm.dm)
    }
    
    var body : some View {
        //TODO: Replace current daemon logic with simpler screen. Home UI should have a toggle connection switch, a short guide accessable with a button, and a register daemon button called "Setup"
        // - Unregister Daemon should be replaced with a full "abort" button that shuts off vpn, deletes routing settings, force closes all openvpn/stunnel instances, clears dns settings, & Unregisters the daemon. This is in case of VPN failure while it's not in a super stable state
        // - TrayApp also needs to update live as VPN status changes. It should also have an icon to represent the attempted reconnect when sleep ends. This will remedy the need to click on it multiple times to determine connection status
        // - Also update Status information to have simple text variations depending on status value. Version is unnecessary
        // - App install needs a short user popup where things like deregistering (if on) and re-registering the daemon can occur for program to function. User needs to allow the daemon in settings, so it should be well-guided. Same with FDA.. until its fixed by including binaries..
        
        VStack(spacing:20) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Stunskin")
            HStack(spacing:10) {
                Text("Debug Buttons (Daemon should be registered with status 1 for usage)")
            
            }
            .padding()
            .background(.gray)
            .cornerRadius(15)
            HStack(spacing: 25) {
                Button("Register Daemon") {
                    dm.register()
                }
                Button("Unregister Daemon") {
                    dm.unregister()
                }
            }
            HStack(spacing: 25) { 
                Text("Status: \(dm.status)")
                Text("Version: \(dm.version)")
                Text("Output: \(dm.output)")
            }
//            HStack(spacing: 25) {
//                Button("Init Connection") {
//                    dm.initConnection()
//                }
//                Button("End Connection") {
//                    dm.endConnection()
//                }
//            }
            
        }
        .padding()
    }
}
