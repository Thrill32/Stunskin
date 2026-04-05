import Foundation
import Security
import ServiceManagement

class DaemonManager {
    public var helperVersion = ""
    public var client = XPCClient()
    public var commandOutput = ""
    public var runResult = false
    
    func register() throws {
        try SMAppService.daemon(plistName: "com.Thrill32.Stunskin.Helper.plist").register()
    }
    func unregister() throws {
        try SMAppService.daemon(plistName: "com.Thrill32.Stunskin.Helper.plist").unregister()
    }
    func status() -> SMAppService.Status {
        SMAppService.daemon(plistName: "com.Thrill32.Stunskin.Helper.plist").status
    }
    func test() {
        client.connect()

        client.getVersion { version in
            DispatchQueue.main.async {
                self.helperVersion = version 
            }
        }
    }
    
    func isRunning() {
        client.connect()
        
        client.isRunning { ans in
            DispatchQueue.main.sync {
                self.runResult = ans
            }
        }
    }
    
    func initConnection(jsonSettings: String) {
        client.connect()
        
        
        client.initVPNConnection(jsonSettings: jsonSettings) { String in } //checkmate horrible code
//        client.disconnect()
    }
    
    func endConnection() {
        client.connect()
        
        client.endVPNConnection() {String in }
//        client.disconnect()
    }
}
