import Foundation
import Network
import notify


class OVPNManager {
    
    enum VPNState {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case failed(Error)
    }
    
    private func postDarwinNotification(_ name: String) {
        notify_post(name)
    }
    
    var onStateChange: ((VPNState) -> Void)?
    var onLog: ((String) -> Void)?
    var onByteCount: ((Int64, Int64) -> Void)?
    
    private var ovpnProcess: Process?
    private var management: OVPNManagement?
    
    private let ovpnPWPath = "/Library/Application Support/Stunskin/tmp/ovpn-mgmt.pw"
    
    func start(configPath: String) throws {
        guard ovpnProcess == nil else { return }
        
        let password = UUID().uuidString
        try setupManagement(password: password)
        try runOVPN(configPath, password: password)
    }
    
    func stop() {
        management?.disconnect()
        management = nil
        ovpnProcess?.terminate()
        ovpnProcess = nil
        cleanupPWFile()
        // Proactively notify disconnection so the tray updates immediately
        onStateChange?(.disconnected)
        postDarwinNotification("com.stunskin.vpn.disconnected")
    }
    
    private func runOVPN(_ configPath: String, password: String) throws {
        let pwFile = URL(fileURLWithPath: ovpnPWPath)
        
        try FileManager.default.createDirectory(
            at: pwFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try password.write(to: pwFile, atomically: true, encoding: .utf8)
        
        let process = Process()
        process.executableURL = Bundle.main.bundleURL
            .appendingPathComponent("openvpn", isDirectory: false)
        process.arguments = [
            "--config", configPath,
            "--management", "127.0.0.1", "7505", pwFile.path,
            "--management-hold",
            "--management-query-passwords"
        ]
        
        process.terminationHandler = { [weak self] _ in
            self?.handleProcessTermination()
        }
        
        try process.run()
        ovpnProcess = process
    }
    
    private func setupManagement(password: String) {
        let mgmt = OVPNManagement(password: password)
        
        mgmt.onStateChange = { [weak self] state in
            switch state {
            case "CONNECTING":
                self?.onStateChange?(.connecting)
                self?.postDarwinNotification("com.stunskin.vpn.connecting")
            case "CONNECTED":
                self?.onStateChange?(.connected)
                self?.postDarwinNotification("com.stunskin.vpn.connected")
            case "DISCONNECTING":
                self?.onStateChange?(.disconnecting)
                self?.postDarwinNotification("com.stunskin.vpn.disconnecting")
            case "EXITING":
                self?.onStateChange?(.disconnected)
                self?.postDarwinNotification("com.stunskin.vpn.disconnected")
            default: break
            }
        }
        
        mgmt.onLog       = { [weak self] log in self?.onLog?(log) }
        mgmt.onByteCount = { [weak self] i, o in self?.onByteCount?(i, o) }
        mgmt.onError = { [weak self] error in
            self?.onStateChange?(.failed(error))
            self?.postDarwinNotification("com.stunskin.vpn.failed")
        }
        
        mgmt.onConnected = { [weak self] in
            mgmt.enableStateStreaming()
            mgmt.enableLogStreaming()
            mgmt.enableByteCountUpdates()
            self?.cleanupPWFile()
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            mgmt.connect()
        }
        
        management = mgmt
    }
    
    private func handleProcessTermination() {
        ovpnProcess = nil
        management = nil
        cleanupPWFile()
        onStateChange?(.disconnected)
        postDarwinNotification("com.stunskin.vpn.disconnected")
    }
    
    private func cleanupPWFile() {
        try? FileManager.default.removeItem(atPath: ovpnPWPath)
    }
}

class OVPNManagement {
    
    var onStateChange: ((String) -> Void)?
    var onLog: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onByteCount: ((Int64, Int64) -> Void)?
    var onError: ((Error) -> Void)?
    
    private var connection: NWConnection?
    private let port: NWEndpoint.Port = 7505
    private var buffer = ""
    private let password: String
    private var didAnnounceConnected = false
    private var didAuthenticate = false
    
    init(password: String) {
        self.password = password
    }
    
    func connect() {
        connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                // Start reading first; authenticate when prompted by the server.
                self.receive()
                // Do not call onConnected here; wait for management prompt/hold.
            case .waiting(let error):
                self.onLog?("Management socket waiting: \(error)")
                self.onError?(error)
            case .failed(let error):
                self.onLog?("Management socket failed: \(error)")
                self.onError?(error)
            default:
                break
            }
        }
        
        connection?.start(queue: .global(qos: .utility))
    }
    
    func disconnect()             { send("signal SIGTERM\n") }
    func enableStateStreaming()   { send("state on\n") }
    func enableLogStreaming()     { send("log on\n") }
    func enableByteCountUpdates() { send("bytecount 2\n") }
    
    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, let str = String(data: data, encoding: .utf8) {
                self.buffer += str
                self.processBuffer()
            }
            if !isComplete && error == nil {
                self.receive()
            }
        }
    }
    
    private func processBuffer() {
        // Detect management password prompt even if not newline-terminated
        if !didAuthenticate, buffer.contains("ENTER PASSWORD:") {
            send("\(password)\n")
            didAuthenticate = true
            // Remove the prompt substring to avoid repeated triggering
            if let range = buffer.range(of: "ENTER PASSWORD:") {
                buffer.removeSubrange(range)
            }
        }
        
        var lines = buffer.components(separatedBy: "\n")
        buffer = lines.removeLast()
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .forEach { handle($0) }
    }
    
    private func handle(_ line: String) {
        // Authenticate to management interface when prompted
        if line.localizedCaseInsensitiveContains("ENTER PASSWORD:") {
            send("\(password)\n")
            didAuthenticate = true
            return
        }
        
        if line.hasPrefix(">HOLD:") {
            // Management is ready; notify and then release the hold
            if !didAnnounceConnected {
                onConnected?()
                didAnnounceConnected = true
            }
            send("hold release\n")
            return
        }
        
        if line.hasPrefix(">STATE:") {
            let parts = line.dropFirst(7).components(separatedBy: ",")
            let state = parts.count > 1 ? String(parts[1]) : "UNKNOWN"
            onStateChange?(state)
            if state == "EXITING" { onDisconnected?() }
            return
        }
        
        if line.hasPrefix(">LOG:") {
            let parts = line.dropFirst(5).components(separatedBy: ",")
            if parts.count > 2 { onLog?(parts[2...].joined(separator: ",")) }
            return
        }
        
        if line.hasPrefix(">BYTECOUNT:") {
            let parts = line.dropFirst(11).components(separatedBy: ",")
            if parts.count == 2,
               let bytesIn  = Int64(parts[0]),
               let bytesOut = Int64(parts[1]) {
                onByteCount?(bytesIn, bytesOut)
            }
            return
        }
        
        if line.hasPrefix(">PASSWORD:") {
            // OpenVPN is requesting user credentials (e.g., Auth or Private Key).
            // This implementation does not supply them; log for visibility.
            onLog?("OpenVPN requested credentials via management: \(line)")
            return
        }
    }
    
    private func send(_ command: String) {
        guard let data = command.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .idempotent)
    }
}

