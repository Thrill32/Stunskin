import Foundation
import SystemConfiguration

class ProfileManager {
    enum infoNotFound: Error {
        case somethingWentWrong
        case fileNotFound(String)
        case invalidInput(String)
    }
    
    public struct Settings : Codable {
        var name: String //user-given identifier
        var targetIP: String
        var DNS: [String]
        var stunnelPath: String
        var OVPNPath: String
    }
    
    func ensureFile(path: String) -> Bool { //creates folder on run and returns if file exists for loading
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: (URL(fileURLWithPath: path).deletingLastPathComponent().path),
                                    withIntermediateDirectories: true)
        }
        
        return fm.fileExists(atPath: path)
        
    }
    
    func scanProfiles(path: String) throws -> [String]? {
        //scan for "stunskinprofile".. renaming will invalidate it (better for manual managing if necessary)
        //naming convention is stunskinprofile-1.json and so on
        
        let fm = FileManager.default
        
        var validFiles: [String] = []
        
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            return nil
        }
        
        for cur in contents {
            let filename: String = URL(fileURLWithPath: cur).lastPathComponent
            
            let delimiters: Set<Character> = ["-", "."]
            
            var sep: [Substring] = filename.split { delimiters.contains($0) }
            
            
            
            if sep.count == 3 && sep[0] == "stunskinprofile" && sep[2] == "json" {
                validFiles.append(cur)
            }
            
        }
        
        if validFiles.isEmpty {
            throw infoNotFound.fileNotFound("No Valid Files")
        }
        return validFiles
    }
    
    public func saveState(path: String, currentData: Settings) {
        ensureFile(path: path)
        let data = try? JSONEncoder().encode(currentData)
        try? data?.write(to: URL(fileURLWithPath: path))
    }

    public func loadState(path: String) throws -> Settings {
        var fail: Settings = Settings(name: "Failsafe Profile", targetIP: "", DNS: [""], stunnelPath: "", OVPNPath: "")
        
        if (!ensureFile(path: path)) { return fail }
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let state = try? JSONDecoder().decode(Settings.self, from: data)
        else {
            throw infoNotFound.invalidInput(path)
        }
        return state
    }
}
