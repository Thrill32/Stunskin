import Foundation

class XPCClient {
    private var connection: NSXPCConnection?
    
    func connect() {
        connection = NSXPCConnection(machServiceName: "com.Thrill32.Stunskin.Helper",
                                     options: .privileged)
        connection?.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection?.invalidationHandler = {
            print("XPC connection invalidated")
        }
        connection?.interruptionHandler = {
            print("XPC connection interrupted")
        }
        connection?.resume()
    }
    
    func getVersion(reply: @escaping (String) -> Void) {
        guard let helper = connection?.remoteObjectProxyWithErrorHandler({ error in
            print("XPC error: \(error)")
            reply("error")
        }) as? HelperProtocol else { return }
        
        helper.getVersion(reply: reply)
    }
    
    func isRunning(reply: @escaping (Bool) -> Void) {
        guard let helper = connection?.remoteObjectProxyWithErrorHandler({ error in
            print("XPC error: \(error)")
            reply(false)
        }) as? HelperProtocol else { return }
        
        helper.isRunning(reply: reply)
    }
    
    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
    
    func initVPNConnection(jsonSettings: String, reply: @escaping (String) -> Void) {
        guard let helper = connection?.remoteObjectProxyWithErrorHandler({ error in
            print("XPC error: \(error)")
            reply("error")
        }) as? HelperProtocol else { return }
        
        print("InitCon on app!")
        helper.initConnection(jsonSettings: jsonSettings, reply: reply)
    }
    
    func endVPNConnection(reply: @escaping (String) -> Void) {
        guard let helper = connection?.remoteObjectProxyWithErrorHandler({ error in
            print("XPC error: \(error)")
            reply("error")
        }) as? HelperProtocol else { return }
        
        print("EndCon on app!")
        helper.endConnection(reply: reply)
    }
}
