import Foundation
import Security
import ServiceManagement
import Combine
import AppKit

public struct FileJSONData : Codable {
    var stunnelConf: String
    var stunnelPem: String
    var OVPNConf: String
}

@MainActor
class DaemonViewModel : ObservableObject {
    @Published var status: SMAppService.Status = .notRegistered
    @Published var version = ""
    @Published var output: String = ""
    
//    public var isInit = false
    
    private let bm: BaseViewModel
    
    let manager = DaemonManager()
    
    func register() {
        try? manager.register()
        status = manager.status()
    }
    func unregister() {
        try? manager.unregister()
        status = manager.status()
    }
    func test() {
        manager.test()
        version = manager.helperVersion
    }
    
    func isRunning() -> Bool {
        manager.isRunning()
        return manager.runResult
    }
    
    func initConnection() {
//        isInit = true
        let json = String(data: try! JSONEncoder().encode(bm.curSettings), encoding: .utf8)!
        
        manager.initConnection(jsonSettings:json)
    }
    
    func extractPemPath(from configContent: String) -> String {
        let pattern = #"^\s*(?:CAfile|cert)\s*=\s*(.+)$"#
        
        let lines = configContent.components(separatedBy: .newlines)
        
        for line in lines {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = regex.firstMatch(in: line, options: [], range: range) {
                    if let pathRange = Range(match.range(at: 1), in: line) {
                        return String(line[pathRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        return ""
    }
    

    func requestFolderPermission(completion: @escaping (URL?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.title = "Select your Stunnel/OpenVPN Configuration Folder"
        openPanel.showsResizeIndicator = true
        openPanel.showsHiddenFiles = false
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                let gainAccess = url.startAccessingSecurityScopedResource()
                
                completion(url)
                
                if gainAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            } else {
                completion(nil)
            }
        }
    }
    
    func newInitConnection() {
        let jsonSettings = String(data: try! JSONEncoder().encode(bm.curSettings), encoding: .utf8)!
        
        let stunnelConfContent = bm.readConf(path: bm.curSettings.stunnelPath)
        
        let extractedPemPath = extractPemPath(from: stunnelConfContent)
        
        let stunnelPemContent = bm.readConf(path: extractedPemPath)
        
        let Files = FileJSONData(
            stunnelConf: stunnelConfContent,
            stunnelPem: stunnelPemContent,
            OVPNConf: bm.readConf(path: bm.curSettings.OVPNPath)
        )
        
        let jsonFiles = String(data: try! JSONEncoder().encode(Files), encoding: .utf8)!
        
        manager.newInitConnection(jsonSettings: jsonSettings, jsonFiles: jsonFiles)
    }
    
    func endConnection() {
//        isInit = false
        manager.endConnection()
    }
    
    public init() {
        bm = BaseViewModel.shared
    }
    
}

