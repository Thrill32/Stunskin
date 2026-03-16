import Foundation
import Security
import ServiceManagement
import Combine

@MainActor
class DaemonViewModel : ObservableObject {
    @Published var status: SMAppService.Status = .notRegistered
    @Published var version = ""
    @Published var output: String = ""
    
    public var isInit = false //should work alright with a simple local toggle as endvpn just kills stunnel and ovpn anyawys
    
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
    func initConnection() {
        isInit = true
        let json = String(data: try! JSONEncoder().encode(bm.curSettings), encoding: .utf8)!
        
        manager.initConnection(jsonSettings:json)
    }
    
    func endConnection() {
        isInit = false
        manager.endConnection()
    }
    
    public init() {
        bm = BaseViewModel.shared
    }
    
}
