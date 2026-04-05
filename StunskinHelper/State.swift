import Foundation
import SystemConfiguration

let stateDir = "/Library/Application Support/Thrill32/Stunskin"
let stateFile = "\(stateDir)/daemon-state.json"


//used for storing configuration data before vpn is run to reset to
//also needs to run at startup for proper settings in case of unexpected shutdown
//[unexp shtd not implemented yet]


public struct Settings : Codable {
    var targetIP: String
    var DNS: [String]
    var stunnelPath: String
    var OVPNPath: String
} //not making a framework rn so manual duplication

class State {
    static let shared = State()
    
    public var currentData = CurrentData(
        running: false,
        initDNS: [],
        initWDNS: [],
        initEDNS: [],
        initRouting: [],
        gatewayIP: "",
        prevSettings: Settings(
           targetIP: "",
           DNS: [],
           stunnelPath: "",
           OVPNPath: ""
        )
    ) //merge gateway into prev at some point
    
    private init() { 
        loadState()
    }
    
    public struct CurrentData : Codable {
        var running: Bool
        var initDNS: [String] //deprecated
        var initWDNS: [String]
        var initEDNS: [String]
        var initRouting: [String]
        var gatewayIP: String
        var prevSettings: Settings
    }
    

    func ensureStateDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: stateDir) {
            try? fm.createDirectory(atPath: stateDir,
                                    withIntermediateDirectories: true)
        }
        
    }

    public func saveState() {
        ensureStateDir()
        let data = try? JSONEncoder().encode(currentData)
        try? data?.write(to: URL(fileURLWithPath: stateFile))
    }

    public func loadState() {
        ensureStateDir()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
              let state = try? JSONDecoder().decode(CurrentData.self, from: data)
        else {
            return
        }
        currentData = state
    }

}

