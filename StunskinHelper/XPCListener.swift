import Foundation
import os.log
import AppKit
import Network

class SleepManager {
    
    let log = OSLog(subsystem: "com.Thrill32.Stunskin.Helper", category: "general")
    
    private var XPC: XPCListener

    private var transition: Bool = false
    
    init(XPC: XPCListener) {
        self.XPC = XPC
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(onWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(onDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
       
    }
    
    private func waitForNetwork(timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "network.monitor")
        var completed = false

        let timeoutWork = DispatchWorkItem {
            guard !completed else { return }
            completed = true
            monitor.cancel()
            completion(false)
        }

        monitor.pathUpdateHandler = { path in
            guard !completed, path.status == .satisfied else { return }
            completed = true
            monitor.cancel()
            DispatchQueue.main.async { completion(true) }
        }

        monitor.start(queue: queue)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
    }
    
    @objc func onWillSleep() {
        os_log("onWillSleep start", log: log, type: .default)
//        NSWorkspace.shared.notificationCenter.removeObserver(self)
        
//        NSWorkspace.shared.notificationCenter.addObserver(
//            self,
//            selector: #selector(onDidWake),
//            name: NSWorkspace.didWakeNotification,
//            object: nil
//        )
       
        if (!XPC.state.currentData.running) {return}

        XPC.endConnection() { String in }
        transition = true
        os_log("onWillSleep attempt end", log: log, type: .default)
    }

    @objc func onDidWake() {
        os_log("onDidWake start", log: log, type: .default)
//        NSWorkspace.shared.notificationCenter.removeObserver(self)
//        NSWorkspace.shared.notificationCenter.addObserver(
//            self,
//            selector: #selector(onWillSleep),
//            name: NSWorkspace.willSleepNotification,
//            object: nil
//        )

        if (!transition) {return}
        transition = false
//        let json = String(data: try! JSONEncoder().encode(XPC.state.currentData.prevSettings), encoding: .utf8)!
//        Thread.sleep(forTimeInterval: 0.5)
        waitForNetwork(timeout: 10) { [weak self] isConnected in
            guard let self else { return }
            if isConnected {
                DispatchQueue.global().async {
                    let json = String(data: try! JSONEncoder().encode(self.XPC.state.currentData.prevSettings), encoding: .utf8)!
                    self.XPC.initConnection(jsonSettings: json) { _ in }
                }
                os_log("onDidWake attempt init", log: log, type: .default)
            }
        }
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

class XPCListener: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private struct CommandResult {
        let output: String
        let status: Int32
        
        var succeeded: Bool {
            status == 0
        }
    }
    
    private enum HelperError: LocalizedError {
        case invalidPayload
        case invalidTargetIP
        case invalidDNS(String)
        case missingConfig(String)
        case missingBinary(String)
        case commandFailed(String)
        case startupFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidPayload:
                return "Invalid VPN settings payload."
            case .invalidTargetIP:
                return "Target IP must be a valid IPv4 or IPv6 address."
            case .invalidDNS(let value):
                return "DNS entry is invalid: \(value)"
            case .missingConfig(let path):
                return "Config file was not found: \(path)"
            case .missingBinary(let name):
                return "Required binary was not found: \(name)"
            case .commandFailed(let message):
                return message
            case .startupFailed(let message):
                return message
            }
        }
    }
    
    private let commandEnvironment = [
        "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin"
    ]
    private let primaryInterface = "en0"
    
    private var stunnelProcess: Process?
    
    let log = OSLog(subsystem: "com.Thrill32.Stunskin.Helper", category: "general")
    
    let listener: NSXPCListener
    let state = State.shared
    
    var sleepMan: SleepManager!

    override init() {
        listener = NSXPCListener(machServiceName: "com.Thrill32.Stunskin.Helper")
        super.init()
        sleepMan = SleepManager(XPC: self) // self is safe to use now
        listener.delegate = self
    }
    
    func start() {
        listener.resume()
        RunLoop.main.run()
    }
    
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
    
    func getVersion(reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }
    
    func isRunning(reply: @escaping (Bool) -> Void) {
        reply(state.currentData.running)
    }
    
    func hasFullDiskAccess() -> Bool {
        let protectedPath = "/Library/Application Support/com.apple.TCC/TCC.db"
        return FileManager.default.isReadableFile(atPath: protectedPath)
    }
    
    private func runCommand(executable: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = commandEnvironment
        
        try process.run()
        process.waitUntilExit()
        
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        
        return CommandResult(output: output, status: process.terminationStatus)
    }
    
    private func validateIPAddress(_ value: String) -> Bool {
        IPv4Address(value) != nil || IPv6Address(value) != nil
    }
    
    private func validateSettings(_ settings: Settings) throws {
        guard validateIPAddress(settings.targetIP) else {
            throw HelperError.invalidTargetIP
        }
        
        for server in settings.DNS where !validateIPAddress(server) {
            throw HelperError.invalidDNS(server)
        }
        
        guard FileManager.default.fileExists(atPath: settings.stunnelPath) else {
            throw HelperError.missingConfig(settings.stunnelPath)
        }
        
        guard FileManager.default.fileExists(atPath: settings.OVPNPath) else {
            throw HelperError.missingConfig(settings.OVPNPath)
        }
    }
    
    private func decodeSettings(from jsonSettings: String) throws -> Settings {
        guard let data = jsonSettings.data(using: .utf8) else {
            throw HelperError.invalidPayload
        }
        
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        try validateSettings(settings)
        return settings
    }
    
    private func stunnelBinaryPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/stunnel",
            "/usr/local/bin/stunnel",
            "/usr/bin/stunnel"
        ]
        
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
    
    private func defaultGateway() throws -> String {
        let result = try runCommand(executable: "/sbin/route", arguments: ["-n", "get", "default"])
        guard result.succeeded else {
            throw HelperError.commandFailed("Unable to read default gateway: \(result.output)")
        }
        
        for line in result.output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                return trimmed.replacingOccurrences(of: "gateway:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        
        throw HelperError.commandFailed("Default gateway was not found in route output.")
    }
    
    private func interfaceAddress(_ interface: String) throws -> String {
        let result = try runCommand(executable: "/usr/sbin/ipconfig", arguments: ["getifaddr", interface])
        guard result.succeeded else {
            throw HelperError.commandFailed("Unable to read address for \(interface): \(result.output)")
        }
        
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func ignoreCommandFailure(executable: String, arguments: [String]) {
        _ = try? runCommand(executable: executable, arguments: arguments)
    }
    
    private func ensureSuccess(_ result: CommandResult, operation: String) throws {
        guard result.succeeded else {
            throw HelperError.commandFailed("\(operation) failed: \(result.output)")
        }
    }
    
    private func isProcessRunning(_ name: String) -> Bool {
        guard let result = try? runCommand(executable: "/usr/bin/pgrep", arguments: ["-x", name]) else {
            return false
        }
        
        return result.succeeded && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var ovpnProcess: Process?

    private func runOVPN(_ configPath: String) throws {
        ovpnProcess = Process()
        ovpnProcess?.executableURL = URL(fileURLWithPath: "/opt/homebrew/sbin/openvpn")
        ovpnProcess?.arguments = ["--config", configPath]
        ovpnProcess?.environment = commandEnvironment
        try ovpnProcess?.run()
    }
    
    private func runStunnel(_ configPath: String) throws {
        guard let binaryPath = stunnelBinaryPath() else {
            throw HelperError.missingBinary("stunnel")
        }
        
        stunnelProcess = Process()
        stunnelProcess?.executableURL = URL(fileURLWithPath: binaryPath)
        stunnelProcess?.arguments = [configPath]
        stunnelProcess?.environment = commandEnvironment
        try stunnelProcess?.run()
    }
    
    func getDNS(_ interface: String) -> [String] {
        guard let result = try? runCommand(
            executable: "/usr/sbin/networksetup",
            arguments: ["-getdnsservers", interface]
        ) else {
            return []
        }
        
        let output = result.output
        if output.contains("Error") || output.contains("not recognized") || output.contains("There aren't any") {
            return []
        }
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    
    private func setDNS(_ servers: [String], service: String) throws {
        let arguments = ["-setdnsservers", service] + (servers.isEmpty ? ["Empty"] : servers)
        let result = try runCommand(executable: "/usr/sbin/networksetup", arguments: arguments)
        try ensureSuccess(result, operation: "Setting DNS for \(service)")
    }
    
    private func availableNetworkServices() throws -> [String] {
        let result = try runCommand(executable: "/usr/sbin/networksetup", arguments: ["-listallnetworkservices"])
        guard result.succeeded else {
            throw HelperError.commandFailed("Listing network services failed: \(result.output)")
        }
        
        return result.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }
    }
    
    private func snapshotDNS(for services: [String]) -> [String: [String]] {
        var dnsByService: [String: [String]] = [:]
        
        for service in services {
            dnsByService[service] = getDNS(service)
        }
        
        return dnsByService
    }
    
    private func restoreDNS(_ dnsByService: [String: [String]]) {
        for (service, servers) in dnsByService {
            try? setDNS(servers, service: service)
        }
    }
    
    private func resetConnectionState() {
        state.currentData.running = false
        state.saveState()
    }
    
    private func rollbackConnectionSetup() {
        ignoreCommandFailure(executable: "/usr/bin/pkill", arguments: ["-x", "stunnel"])
        ignoreCommandFailure(executable: "/usr/bin/pkill", arguments: ["-x", "openvpn"])
        
        if !state.currentData.prevSettings.targetIP.isEmpty, !state.currentData.gatewayIP.isEmpty {
            ignoreCommandFailure(
                executable: "/sbin/route",
                arguments: ["-n", "delete", "-host", state.currentData.prevSettings.targetIP, state.currentData.gatewayIP, "-ifscope", primaryInterface]
            )
        }
        
        if let address = try? interfaceAddress(primaryInterface), !state.currentData.prevSettings.targetIP.isEmpty {
            ignoreCommandFailure(
                executable: "/sbin/route",
                arguments: ["-n", "delete", "-host", state.currentData.prevSettings.targetIP, address, "-ifscope", primaryInterface]
            )
        }
        
        restoreDNS(state.currentData.initDNSByService)
        
        resetConnectionState()
    }
    
    func initConnection(jsonSettings:String, reply: @escaping (String) -> Void) {
        os_log("initConnection start", log: log, type: .default)
        resetConnectionState()
        
        do {
            let curSettings = try decodeSettings(from: jsonSettings)
            state.currentData.prevSettings = curSettings
            
            state.currentData.gatewayIP = try defaultGateway()
            let interfaceIP = try interfaceAddress(primaryInterface)
            
            ignoreCommandFailure(
                executable: "/sbin/route",
                arguments: ["-n", "delete", "-host", curSettings.targetIP, state.currentData.gatewayIP]
            )
            ignoreCommandFailure(
                executable: "/sbin/route",
                arguments: ["-n", "delete", "-host", curSettings.targetIP, interfaceIP, "-ifscope", primaryInterface]
            )
            
            try ensureSuccess(
                runCommand(
                    executable: "/sbin/route",
                    arguments: ["-n", "add", "-host", curSettings.targetIP, state.currentData.gatewayIP, "-ifscope", primaryInterface]
                ),
                operation: "Adding route for \(curSettings.targetIP)"
            )
            
            let services = try availableNetworkServices()
            state.currentData.initDNSByService = snapshotDNS(for: services)
            state.currentData.initWDNS = state.currentData.initDNSByService["Wi-Fi"] ?? []
            state.currentData.initEDNS = state.currentData.initDNSByService["Ethernet"] ?? []
            
            for service in services {
                try setDNS(curSettings.DNS, service: service)
            }
            
            try runStunnel(curSettings.stunnelPath)
            os_log("stunnel start: %{public}@", log: log, type: .default, curSettings.stunnelPath)
            
            Thread.sleep(forTimeInterval: 0.1)
            try runOVPN(curSettings.OVPNPath)
            
            Thread.sleep(forTimeInterval: 0.8)
            
            let stunnelRunning = isProcessRunning("stunnel")
            let openVPNRunning = isProcessRunning("openvpn")
            guard stunnelRunning, openVPNRunning else {
                throw HelperError.startupFailed(
                    "VPN startup validation failed. stunnel running: \(stunnelRunning), openvpn running: \(openVPNRunning)"
                )
            }
            
            state.currentData.running = true
            state.saveState()
            reply("Success")
            
            let curFDA = hasFullDiskAccess() ? "Active" : "Inactive"
            os_log("InitSaveSuccess, FDA: %{public}@", log: log, type: .default, curFDA)
        } catch {
            rollbackConnectionSetup()
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            os_log("initConnection failed: %{public}@", log: log, type: .error, message)
            reply("Failure: \(message)")
        }
    }
    
    func endConnection(reply: @escaping (String) -> Void) {
        os_log("endConnection start", log: log, type: .default)
        
        ignoreCommandFailure(executable: "/usr/bin/pkill", arguments: ["-x", "stunnel"])
        ignoreCommandFailure(executable: "/usr/bin/pkill", arguments: ["-x", "openvpn"])
        
        if !state.currentData.prevSettings.targetIP.isEmpty, !state.currentData.gatewayIP.isEmpty {
            ignoreCommandFailure(
                executable: "/sbin/route",
                arguments: ["-n", "delete", "-host", state.currentData.prevSettings.targetIP, state.currentData.gatewayIP, "-ifscope", primaryInterface]
            )
        }
        
        if let address = try? interfaceAddress(primaryInterface), !state.currentData.prevSettings.targetIP.isEmpty {
            ignoreCommandFailure(
                executable: "/sbin/route",
                arguments: ["-n", "delete", "-host", state.currentData.prevSettings.targetIP, address, "-ifscope", primaryInterface]
            )
        }
        
        restoreDNS(state.currentData.initDNSByService)
        
        state.currentData.running = false
        state.saveState()
        reply("Success")
    }
}
