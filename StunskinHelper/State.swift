import Foundation
import SystemConfiguration

let stateDir = "/Library/Application Support/Thrill32/Stunskin"
let stateFile = "\(stateDir)/daemon-state.json"


//used for storing configuration data before vpn is run to reset to

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
        initDNSByService: [:],
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
        var initDNSByService: [String: [String]]
        var initRouting: [String]
        var gatewayIP: String
        var prevSettings: Settings
        
        init(
            running: Bool,
            initDNS: [String],
            initWDNS: [String],
            initEDNS: [String],
            initDNSByService: [String: [String]],
            initRouting: [String],
            gatewayIP: String,
            prevSettings: Settings
        ) {
            self.running = running
            self.initDNS = initDNS
            self.initWDNS = initWDNS
            self.initEDNS = initEDNS
            self.initDNSByService = initDNSByService
            self.initRouting = initRouting
            self.gatewayIP = gatewayIP
            self.prevSettings = prevSettings
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            running = try container.decode(Bool.self, forKey: .running)
            initDNS = try container.decodeIfPresent([String].self, forKey: .initDNS) ?? []
            initWDNS = try container.decodeIfPresent([String].self, forKey: .initWDNS) ?? []
            initEDNS = try container.decodeIfPresent([String].self, forKey: .initEDNS) ?? []
            initDNSByService = try container.decodeIfPresent([String: [String]].self, forKey: .initDNSByService) ?? [:]
            initRouting = try container.decodeIfPresent([String].self, forKey: .initRouting) ?? []
            gatewayIP = try container.decodeIfPresent(String.self, forKey: .gatewayIP) ?? ""
            prevSettings = try container.decode(Settings.self, forKey: .prevSettings)
        }
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
