import Foundation
import Security
import ServiceManagement
import Combine

public struct FileJSONData : Codable {
    var stunnelConf: String
    var stunnelPem: String
    var OVPNConf: String
}

@MainActor
class DaemonViewModel : ObservableObject {
    @Published var status: SMAppService.Status = .notRegistered
    @Published var version = ""
    @Published var output: String = ""
    
//    public var isInit = false
    
    private let bm: BaseViewModel
    
    private let manager = DaemonManager()
    
    func register() {
        try? manager.register()
        status = manager.status()
    }
    func unregister() {
        try? manager.unregister()
        status = manager.status()
    }
    func test() {
        manager.test()
        version = manager.helperVersion
    }
    
    func isRunning() -> Bool {
        manager.isRunning()
        return manager.runResult
    }
    
    func initConnection() {
//        isInit = true
        let json = String(data: try! JSONEncoder().encode(bm.curSettings), encoding: .utf8)!
        
        manager.initConnection(jsonSettings:json)
    }
    
    func newInitConnection() {
        let jsonSettings = String(data: try! JSONEncoder().encode(bm.curSettings), encoding: .utf8)!
        
        let Files = FileJSONData(
            stunnelConf: bm.readConf(path: bm.curSettings.stunnelPath),
            stunnelPem: bm.readConf(path: ""), //TODO: read pemfile loc from stunnel conf
            OVPNConf: bm.readConf(path: bm.curSettings.OVPNPath)
        )
        
        let jsonFiles = String(data: try! JSONEncoder().encode(Files), encoding: .utf8)!
        
        
        manager.newInitConnection(jsonSettings: jsonSettings, jsonFiles: jsonFiles)
    }
    
    func endConnection() {
//        isInit = false
        manager.endConnection()
    }
    
    public init() {
        bm = BaseViewModel.shared
    }
    
}
