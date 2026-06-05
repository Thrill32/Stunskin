import Foundation
import os.log
import AppKit
import Network
import notify

//TODO: Largely rework daemon functionality. Native alternatives to CLIs should be used. Openvpn and stunnel should also be packaged with the app to remove the need to full disk access. Will need to check out liscencing information for that, but both should be GLPv2

//TODO: Convert binaries to json and send through XPC. Can store in /Library/Application Support if necessary. FDA is a file permissions issue, not an OpenVPN one.

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
                    let jsonFiles = self.XPC.state.currentData.prevFilesJSON
                    self.XPC.newInitConnection(jsonSettings: json, jsonFiles: jsonFiles) { _ in }
                }
                os_log("onDidWake attempt init", log: log, type: .default)
            }
        }
    }
    
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

public struct FileJSONData : Codable {
    var stunnelConf: String
    var stunnelPem: String
    var OVPNConf: String
}

let globlog = OSLog(subsystem: "com.Thrill32.Stunskin.Helper", category: "general")
public func errlog(_ text: String) {
    os_log("%{public}@ from Stunskin", log: globlog, type: .error, text)
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
        "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" //removed homebrew
    ]
    private let primaryInterface = "en0"
    
    private var stunnelProcess: Process?
    
    let log = OSLog(subsystem: "com.Thrill32.Stunskin.Helper", category: "general")
    
    let listener: NSXPCListener
    let state = State.shared
    
    var sleepMan: SleepManager?
    private var vpn: OVPNManager?

    override init() {
        listener = NSXPCListener(machServiceName: "com.Thrill32.Stunskin.Helper")
        super.init()
        
        // Fully initialized now, safe to use `self`
        self.sleepMan = SleepManager(XPC: self)
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
    
    private var OVPNPWPath = "/Library/Application Support/Stunskin/tmp/ovpn-mgmt.pw"
    
    private func runOVPN(_ configPath: String) throws {
        ovpnProcess = Process()
//        ovpnProcess?.executableURL = URL(fileURLWithPath: "/opt/homebrew/sbin/openvpn")
        
        ovpnProcess?.executableURL = Bundle.main.bundleURL
            .appendingPathComponent("openvpn", isDirectory: false)
//        ovpnProcess?.arguments = ["--config", configPath]
        
        let password = UUID().uuidString
        let pwFile = URL(fileURLWithPath: OVPNPWPath)
        try password.write(to: pwFile, atomically: true, encoding: .utf8)

        ovpnProcess?.arguments = [
            "--config", configPath,
            "--management", "localhost", "7505", pwFile.path,
            "--management-hold",
            "--management-query-passwords"
        ]
        
//        ovpnProcess?.environment = commandEnvironment
        try ovpnProcess?.run()
    }
    
    private func runStunnel(_ configPath: String) throws {
//        guard let binaryPath = stunnelBinaryPath() else {
//            throw HelperError.missingBinary("stunnel")
//        }
        
        stunnelProcess = Process()
//        stunnelProcess?.executableURL = URL(fileURLWithPath: binaryPath)
        stunnelProcess?.executableURL = Bundle.main.bundleURL
        .appendingPathComponent("stunnel", isDirectory: false)
        stunnelProcess?.arguments = [configPath]
//        stunnelProcess?.environment = commandEnvironment
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
    
//    func initConnection(jsonSettings:String, reply: @escaping (String) -> Void) {
//        os_log("initConnection start", log: log, type: .default)
//        resetConnectionState()
//        
////        os_log("Stunskin path: %{public}@", log: log, type: .error, Bundle.main.bundleURL.path) //this worked and pointed to .../Content/Helpers/
//        do {
//            let curSettings = try decodeSettings(from: jsonSettings)
//            state.currentData.prevSettings = curSettings
//            
//            state.currentData.gatewayIP = try defaultGateway()
//            let interfaceIP = try interfaceAddress(primaryInterface)
//            
//            ignoreCommandFailure(
//                executable: "/sbin/route",
//                arguments: ["-n", "delete", "-host", curSettings.targetIP, state.currentData.gatewayIP]
//            )
//            ignoreCommandFailure(
//                executable: "/sbin/route",
//                arguments: ["-n", "delete", "-host", curSettings.targetIP, interfaceIP, "-ifscope", primaryInterface]
//            )
//            
//            try ensureSuccess(
//                runCommand(
//                    executable: "/sbin/route",
//                    arguments: ["-n", "add", "-host", curSettings.targetIP, state.currentData.gatewayIP, "-ifscope", primaryInterface]
//                ),
//                operation: "Adding route for \(curSettings.targetIP)"
//            )
//            
//            let services = try availableNetworkServices()
//            state.currentData.initDNSByService = snapshotDNS(for: services)
//            state.currentData.initWDNS = state.currentData.initDNSByService["Wi-Fi"] ?? []
//            state.currentData.initEDNS = state.currentData.initDNSByService["Ethernet"] ?? []
//            
//            for service in services {
//                try setDNS(curSettings.DNS, service: service)
//            }
//            
//            try runStunnel(curSettings.stunnelPath)
//            os_log("stunnel start: %{public}@", log: log, type: .default, curSettings.stunnelPath)
//            
//            Thread.sleep(forTimeInterval: 0.1) //TODO: replace thread.sleep
//            try runOVPN(curSettings.OVPNPath)
//            os_log("OVPN start: %{public}@", log: log, type: .default, curSettings.OVPNPath)
//            
//            Thread.sleep(forTimeInterval: 0.8)
//            
//            let stunnelRunning: Bool! = isProcessRunning("stunnel")
//            let openVPNRunning: Bool! = isProcessRunning("openvpn")
//            
//            os_log("OVPN: %{public}s | Stunnel: %{public}s", log: log, type: .error, String(openVPNRunning), String(stunnelRunning))
//            
//            guard stunnelRunning, openVPNRunning else {
//                throw HelperError.startupFailed(
//                    "VPN startup validation failed. stunnel running: \(stunnelRunning), openvpn running: \(openVPNRunning)"
//                )
//            }
//            
//            state.currentData.running = true
//            state.saveState()
//            reply("Success")
//            
//            let curFDA = hasFullDiskAccess() ? "Active" : "Inactive"
//            os_log("InitSaveSuccess, FDA: %{public}@", log: log, type: .default, curFDA)
//        } catch {
//            rollbackConnectionSetup()
//            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
//            os_log("initConnection failed: %{public}@", log: log, type: .error, message)
//            reply("Failure: \(message)")
//        }
//    }
    
    private func decodeFiles(from jsonFiles: String) throws -> FileJSONData {
        guard let data = jsonFiles.data(using: .utf8) else {
            throw HelperError.invalidPayload
        }
        
        let file = try JSONDecoder().decode(FileJSONData.self, from: data)
        return file
    }
    
    private func readFileString(_ filePath: String) -> String? {
        let fileURL = URL(fileURLWithPath: filePath)
        do {
            let rawData = try Data(contentsOf: fileURL)
            return String(data: rawData, encoding: .utf8)
        } catch {
            print("Error reading file: \(error)")
            return nil
        }
    }
    
    func cleanTmpDirectory() throws {
        let fm = FileManager.default
        let tmpURL = URL(fileURLWithPath: "/Library/Application Support/Stunskin/tmp")
        let extensionsToDelete: Set<String> = ["conf", "pem", "ovpn"]
        
        let files = try fm.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil)
        
        for file in files where extensionsToDelete.contains(file.pathExtension) {
            try fm.removeItem(at: file)
        }
    }
    
    func newInitConnection(jsonSettings: String, jsonFiles: String, reply: @escaping (String) -> Void) {
        
        os_log("initConnection start v2", log: log, type: .default)
        resetConnectionState()
        do {
            try cleanTmpDirectory()

            let curSettings = try decodeSettings(from: jsonSettings)
            state.currentData.prevSettings = curSettings
            state.currentData.prevFilesJSON = jsonFiles
            
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
            
            var Files: FileJSONData = try decodeFiles(from: jsonFiles)
            
            errlog("trywrite ovpnconf")
            
            try Files.OVPNConf.write(
                to: URL(fileURLWithPath: "/Library/Application Support/Stunskin/tmp/curovpn.ovpn"),
                atomically: true,
                encoding: .utf8
            )
            
            errlog("trywrite stunnelpem")
            
            try Files.stunnelPem.write(
                to: URL(fileURLWithPath: "/Library/Application Support/Stunskin/tmp/curpem.pem"),
                atomically: true,
                encoding: .utf8
            )
            
            errlog("trywrite stunnelconf")
            
            try Files.stunnelConf.write(
                to: URL(fileURLWithPath: "/Library/Application Support/Stunskin/tmp/curstunconf.conf"),
                atomically: true,
                encoding: .utf8
            )
            
            
            var newStunnelConf = Files.stunnelConf.replacingOccurrences(
                of: #"CAfile = .*"#,
                with: "CAfile = /Library/Application Support/Stunskin/tmp/curpem.pem",
                options: .regularExpression
            )
            errlog("trywrite newstunnelconf (mod cert)")
            try newStunnelConf.write(to: URL(fileURLWithPath: "/Library/Application Support/Stunskin/tmp/curstunconf.conf"), atomically: true, encoding: .utf8)
            
            errlog("tryrun stunnel")
            try runStunnel("/Library/Application Support/Stunskin/tmp/curstunconf.conf")
            os_log("stunnel start: %{public}@", log: log, type: .default, curSettings.stunnelPath)
            
//            try runOVPN("/Library/Application Support/Stunskin/tmp/curovpn.ovpn")
            errlog("trycreate vpn")
            vpn = OVPNManager()

            vpn?.onStateChange = { [weak self] state in
                guard let self else { return }
                switch state {
                case .connecting:
                    os_log("OVPN state: connecting", log: self.log, type: .default)
                case .connected:
                    os_log("OVPN state: connected", log: self.log, type: .default)
                    self.state.currentData.running = true
                    self.state.saveState()
                case .disconnecting:
                    os_log("OVPN state: disconnecting", log: self.log, type: .default)
                case .disconnected:
                    os_log("OVPN state: disconnected", log: self.log, type: .default)
                    self.rollbackConnectionSetup()
                case .failed(let error):
                    os_log("OVPN state: failed %{public}@", log: self.log, type: .error, String(describing: error))
                    self.rollbackConnectionSetup()
                }
            }
            
//            vpn.onLog       = { log  in }
//            vpn.onByteCount = { i, o in }
            errlog("attempt vpn start. time: " + String(Date.now.formatted()))
            try vpn!.start(configPath: "/Library/Application Support/Stunskin/tmp/curovpn.ovpn")
            os_log("ovpn start: %{public}@", log: log, type: .default, "/Library/Application Support/Stunskin/tmp/curovpn.ovpn")
            
//            errlog("isprocrun")
//            let stunnelRunning: Bool! = isProcessRunning("stunnel")
//            let openVPNRunning: Bool! = isProcessRunning("openvpn")
//            
//            guard stunnelRunning, openVPNRunning else {
//                throw HelperError.startupFailed(
//                    "VPN startup validation failed. stunnel running: \(stunnelRunning), openvpn running: \(openVPNRunning)"
//                )
//            }
//            errlog("attempt save")
//            state.currentData.running = true
//            state.saveState()
            
            reply("Success")
            
            os_log("InitSaveSuccess", log: log, type: .default)
            
        } catch {
            rollbackConnectionSetup()
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            os_log("initConnection failed: %{public}@", log: log, type: .error, message)
            reply("Failure: \(message)")
        }
    }
    
    func endConnection(reply: @escaping (String) -> Void) {
        os_log("endConnection start", log: log, type: .default)
        errlog("endconnection starting. time: " + String(Date.now.formatted()))
        ignoreCommandFailure(executable: "/usr/bin/pkill", arguments: ["-x", "stunnel"])
//        ignoreCommandFailure(executable: "/usr/bin/pkill", arguments: ["-x", "openvpn"])
        if let vpn = vpn {
            vpn.stop()
            self.vpn = nil
        }
        
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
        notify_post("com.stunskin.vpn.disconnected")
        reply("Success")
    }
}

