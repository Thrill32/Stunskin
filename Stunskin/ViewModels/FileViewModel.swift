//quicksetup by selecting folder with stuninstall info

import SwiftUI
import Combine
import Foundation
import ServiceManagement

enum infoNotFound: Error {
    case somethingWentWrong
    case fileNotFound(String)
    case invalidInput(String)
}

class FileViewModel : ObservableObject {
    private let bm: BaseViewModel
    
    func readFolder(stunInfoPath: String) {
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: stunInfoPath)
        
        do {
            let items = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil
            )
            
            let confFiles = items.filter { $0.pathExtension == "conf" }
            let ovpnFiles = items.filter { $0.pathExtension == "ovpn" }
            let pemFiles  = items.filter { $0.pathExtension == "pem" }
            
            var targetIP: String
            var pemPath: String?
            
            guard let pemFile = pemFiles.first,
                  let confFile = confFiles.first,
                  let ovpnFile = ovpnFiles.first else {
                throw infoNotFound.invalidInput("missing required files")
            }

            pemPath = pemFile.path
            
            
            //conf
            
            let contents = try String(contentsOf: confFile, encoding: .utf8)
            
            let scanner = Scanner(string: contents)
            
            scanner.scanUpToString("connect = ")
            scanner.scanString("connect = ")
            
            if let foundIP = scanner.scanUpToString(":") {
                targetIP = foundIP
                bm.curSettings.targetIP = targetIP
                
                var newContents = contents.replacingOccurrences(
                    of: #"CAfile = .*"#,
                    with: "CAfile = \(pemPath!)",
                    options: .regularExpression
                )
                
                try newContents.write(to: confFile, atomically: true, encoding: .utf8)
                
            
                bm.curSettings.stunnelPath = confFile.path
            } else {
                throw infoNotFound.invalidInput(contents)
            }
        
            //ovpn
            bm.curSettings.OVPNPath = ovpnFile.path
            
            
        } catch {
            print("Error: \(error)")
        }
    }
    
    public init() {
        bm = BaseViewModel.shared
    }
}
