import Foundation

@objc protocol HelperProtocol {
    func getVersion(reply: @escaping (String) -> Void)
    func isRunning(reply: @escaping (Bool) -> Void)
    func initConnection(jsonSettings: String, reply: @escaping (String) -> Void)
    func endConnection(reply: @escaping (String) -> Void)
}
