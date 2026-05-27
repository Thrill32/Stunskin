import SwiftUI
import Combine
import Foundation
import ServiceManagement

import os.log
let log = OSLog(subsystem: "com.Thrill32.Stunskin", category: "general")

public struct Settings : Codable {
    var targetIP: String
    var DNS: [String]
    var stunnelPath: String
    var OVPNPath: String
}


class BaseViewModel : ObservableObject {
    public static let shared = BaseViewModel()
    
    public lazy var dm: DaemonViewModel = DaemonViewModel()
    public lazy var fm: FileViewModel = FileViewModel()
    
//    @Published var stunnelConfPath = #""# {
//        didSet { UserDefaults.standard.set(stunnelConfPath, forKey: "stunnelConfPath")
//        }
//    }
//    @Published var OVPNConfPath = #""# {
//        didSet { UserDefaults.standard.set(OVPNConfPath, forKey: "OVPNConfPath")
//        }
//    }
    @Published var stunnelConfContent : String = ""
    @Published var OVPNConfContent : String = ""
    
    @Published var curSettings : Settings {
        didSet { UserDefaults.standard.set(toJSON(cs: curSettings), forKey: "curSettingsJSON")
        }
    }
    
    func readConf(path: String?) -> String { //accept string/null and handle returning empty
        guard let path = path, !path.isEmpty else { return "" }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
    
    func toJSON(cs:Settings) -> String {
        return String(data: try! JSONEncoder().encode(cs), encoding: .utf8)!
    }
    
    func fromJSON(js: String) throws -> Settings {
        let data = js.data(using: .utf8) ?? Data()
        return try JSONDecoder().decode(Settings.self, from: data)
    }
    
    init() {
        let defaults = UserDefaults.standard
        
        self.curSettings = Settings(targetIP: "", DNS: [], stunnelPath: "", OVPNPath: "")
        
        self.curSettings = (try? fromJSON(js: defaults.string(forKey: "curSettingsJSON") ?? "")) ?? Settings(targetIP: "", DNS: [], stunnelPath: "", OVPNPath: "")
        stunnelConfContent = readConf(path: self.curSettings.stunnelPath)
        OVPNConfContent = readConf(path: self.curSettings.OVPNPath)
    }
    
    
    
    
    
}




