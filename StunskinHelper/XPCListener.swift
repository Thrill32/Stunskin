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
    
    // MARK: - HelperProtocol
    func getVersion(reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }
    
    func hasFullDiskAccess() -> Bool {
        let protectedPath = "/Library/Application Support/com.apple.TCC/TCC.db"
        return FileManager.default.isReadableFile(atPath: protectedPath)
    }
    
    private func runCommand(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = [
            "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin"
        ]
        
        do {
            try process.launch()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? "no output"
        } catch {
            return "error: \(error)"
        }
    }
    
    private var ovpnProcess: Process?

    private func runOVPN(_ command: String) { //needs full disk access for this or else sandboxd will prevent it... even if it has root?
        ovpnProcess = Process()
        ovpnProcess?.executableURL = URL(fileURLWithPath: "/opt/homebrew/sbin/openvpn")
        ovpnProcess?.arguments = ["--config", command]
        ovpnProcess?.environment = [
            "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin"
        ]
        try? ovpnProcess?.run()
    }
    
    func getDNS(_ interface: String) -> [String] { //REDO THIS BROKEN FUNCTION!!! or the parser doesnt work with joined? check how it goes down
        let output = runCommand("networksetup -getdnsservers \(interface)")
        if output.contains("Error") || output.contains("not recognized") || output.contains("There aren't any") {
            return []
        }
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    
    func initConnection(jsonSettings:String, reply: @escaping (String) -> Void) {
        
        
        os_log("initConnection start", log: log, type: .default)
        
        let data = jsonSettings.data(using: .utf8)!
        let curSettings = try! JSONDecoder().decode(Settings.self, from: data)
        
        var stunnelPath = curSettings.stunnelPath
        var OVPNPath = curSettings.OVPNPath
        
        state.currentData.prevSettings = curSettings
        
        //also we're root so dont use sudo for no reason
    
        
        let gwResult = runCommand("route -n get default | awk '/gateway/ {print $2}'")
        state.currentData.gatewayIP = gwResult.trimmingCharacters(in: .whitespacesAndNewlines)
        os_log("gateway: C", log: log, type: .default, state.currentData.gatewayIP) //why is this gateway: C???? why did I do this? change later?
        // delete any stale routes first
        runCommand("route -n delete -host \(curSettings.targetIP) \(state.currentData.gatewayIP)")
        runCommand("route -n delete -host \(curSettings.targetIP) \(runCommand("ipconfig getifaddr en0").trimmingCharacters(in: .whitespacesAndNewlines)) -ifscope en0")
        
        // then add fresh
        runCommand("route -n add -host \(curSettings.targetIP) \(state.currentData.gatewayIP) -ifscope en0") //maybe make en0 changeable in the future
        
        
        state.currentData.initWDNS = []; state.currentData.initEDNS = []
        state.currentData.initWDNS += getDNS("Wi-Fi")
        state.currentData.initEDNS += getDNS("Ethernet")
        
        runCommand("networksetup -setdnsservers Wi-Fi \(curSettings.DNS.joined(separator: " "))")
        runCommand("networksetup -setdnsservers Ethernet \(curSettings.DNS.joined(separator: " "))")
        
        
        runCommand("stunnel \(stunnelPath)")
        os_log("stunnel start: %{public}@", log: log, type: .default, stunnelPath)
        
        Thread.sleep(forTimeInterval: 0.1)
        runOVPN(OVPNPath)
        
        state.currentData.running = true
        
        Thread.sleep(forTimeInterval: 0.8) //we wait

        let ovpnRunning = runCommand("pgrep -x openvpn")
        os_log("openvpn PID: %{public}@", log: log, type: .default, ovpnRunning)
        
        state.saveState()
        reply("Success")
        var curFDA : String = hasFullDiskAccess() ? "Active" : "Inactive"
        
        os_log("InitSaveSuccess, FDA: %{public}@", log: log, type: .default, curFDA)
    }
    
    func endConnection(reply: @escaping (String) -> Void) {
        os_log("endConnection start", log: log, type: .default)
        runCommand("pkill stunnel") //absolute cinema
        runCommand("pkill openvpn") //we do NOT care about clean shutoff.. it works completely fine like this
        
        runCommand("route -n delete -host \(state.currentData.prevSettings.targetIP) \(state.currentData.gatewayIP) -ifscope en0")
        runCommand("route -n delete -host \(state.currentData.prevSettings.targetIP) \(runCommand("ipconfig getifaddr en0").trimmingCharacters(in: .whitespacesAndNewlines)) -ifscope en0")
        
        var WSep = state.currentData.initWDNS.joined(separator: " ")
        var ESep = state.currentData.initEDNS.joined(separator: " ")
        
        if (WSep=="" || WSep==" ") {
            WSep = "Empty"
        }
        if (ESep=="" || ESep==" ") {
            ESep = "Empty"
        }
        
        runCommand("networksetup -setdnsservers Wi-Fi \(WSep)")
        runCommand("networksetup -setdnsservers Ethernet \(ESep)")
        
        state.currentData.running = false
        state.saveState()
        reply("Success")
    }
}
