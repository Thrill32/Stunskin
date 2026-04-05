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
        VStack(spacing:20) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Stunskin")
            HStack(spacing:10) {
                Text("Sample Text")
                Text("A")
                    .background(.yellow.opacity(0.4))
            
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
            HStack(spacing: 25) {
                Button("Init Connection") {
                    dm.initConnection()
                }
                Button("End Connection") {
                    dm.endConnection()
                }
            }
            
        }
        .padding()
    }
}
