import Foundation
import SystemConfiguration

class ProfileManager {
//    public static let corePath = URL(fileURLWithPath: "/Library/Application Support/Stunskin")
    public static let corePath: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            
        return appSupport.appendingPathComponent("Stunskin")
    }()
    
    enum infoNotFound: Error {
        case somethingWentWrong
        case fileNotFound(String)
        case invalidInput(String)
    }
    
    
    public static func ensureFile(path: String) -> Bool { //creates folder on run and returns if file exists for loading
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: (URL(fileURLWithPath: path).deletingLastPathComponent().path),
                                    withIntermediateDirectories: true)
        }
        
        return fm.fileExists(atPath: path)
        
    }
    
    public static func toJSON(cs:Settings) -> String {
        return String(data: try! JSONEncoder().encode(cs), encoding: .utf8)!
    }
    
    public static func fromJSON(js: String) throws -> Settings {
        let data = js.data(using: .utf8) ?? Data()
        return try JSONDecoder().decode(Settings.self, from: data)
    }
    
    public static func scanProfiles(path: String) throws -> [String]? {
        //scan for "stunskinprofile".. renaming will invalidate it (better for manual managing if necessary)
        //naming convention is stunskinprofile-name.json
        //name is user-chosen and will be displayed in profiler selector rather than full file name
        
        let fm = FileManager.default
        
        var validFiles: [String] = []
        
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            return nil
        }
        
        for cur in contents {
//            print("Try: " + cur)
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
    
    public static func saveState(path: String, currentData: Settings) {
        ensureFile(path: path)
        let data = try? JSONEncoder().encode(currentData)
        try? data?.write(to: URL(fileURLWithPath: path))
    }

    public static func loadState(path: String) throws -> Settings {
        let fail: Settings = Settings(targetIP: "", DNS: [""], stunnelPath: "", OVPNPath: "") //failsafe profile rather than throwing an exception
        
        if (!ensureFile(path: path)) {
            throw infoNotFound.fileNotFound(path + " not found.")
        }
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let state = try? JSONDecoder().decode(Settings.self, from: data)
        else {
            throw infoNotFound.invalidInput(path)
        }
        print(state.targetIP + state.stunnelPath)
        return state
    }
    
    public static func deleteProfile(path: URL) {
        let fm = FileManager.default
        
        if ensureFile(path: path.path) { //Good naming conventions
            do {
                try fm.removeItem(at: path)
            } catch {
                print("Failed to delete profile: \(error.localizedDescription)")
            }
        } else {
            print("Profile doesn't exist")
        }
    }
    
    public static func simplifyProfileName(_ content: String) -> String {
        return content
            .replacingOccurrences(of: ".json", with: "")
            .replacingOccurrences(of: "stunskinprofile-", with: "")
    }
    
    public static func simpleToURL(_ content: String) -> URL {
        return ProfileManager.corePath
            .appendingPathComponent("stunskinprofile-" + (
                content
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: "-", with: ""))
              + ".json")
    }
}
