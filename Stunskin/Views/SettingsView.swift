import SwiftUI

func getPath() -> String { //pretty sure this is reserved on ios
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false

    if panel.runModal() == .OK {
        return panel.url?.path ?? ""
    }
    return #""#
}

func saveTo(content: String, path: String) {
    let allowed = [".conf", ".ovpn"]
    if !allowed.contains(where: { path.hasSuffix($0) }) {
        print("Not a conf file..pls dont mess up stuff")
        return
    }
    do {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        print("Save failed: \(error)")
    }
}

struct SettingsView : View {
    @ObservedObject private var bm : BaseViewModel
    
    init(pbm: BaseViewModel) {
        bm = pbm
    }
    
    var body: some View {
        VStack(spacing:15) {
            DisclosureGroup("Stunnel") {
                VStack {
                    HStack(spacing:10) {
                        TextField("Stunnel .conf Path", text:$bm.curSettings.stunnelPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse") {
                            DispatchQueue.main.async {
                                let path = getPath()
                                bm.curSettings.stunnelPath = path
                                bm.stunnelConfContent = bm.readConf(path: path)
                                
                            }
                        }
                    }
                    TextEditor(text: $bm.stunnelConfContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .padding(8)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3)))
                    Button("Save Conf") {
                        saveTo(content: bm.stunnelConfContent, path: bm.curSettings.stunnelPath)
                    }
                    
                }
            }
            DisclosureGroup("OpenVPN") {
                VStack {
                    HStack(spacing:10) {
                        TextField("OpenVPN .ovpn Path", text:$bm.curSettings.OVPNPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse") {
                            DispatchQueue.main.async {
                                let path = getPath()
                                bm.curSettings.OVPNPath = path
                                bm.OVPNConfContent = bm.readConf(path: path)
                            }
                        }
                    }
                    TextEditor(text: $bm.OVPNConfContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .padding(8)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3)))
                    Button("Save Conf") {
                        saveTo(content: bm.OVPNConfContent, path: bm.curSettings.OVPNPath)
                    }
                    
                }
            }
            DisclosureGroup("General Settings") {
                VStack(spacing: 10) {
                    
                    TextField("Target IP Address", text:$bm.curSettings.targetIP)
                            .textFieldStyle(.roundedBorder)
                    TextField("Target DNS (Separated by commas)", text: Binding(
                        get: { bm.curSettings.DNS.joined(separator: ", ") },
                        set: { bm.curSettings.DNS = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder)}
            } //ok i made like 50 million changes without testing a single one apple please
            Spacer()
        }.padding()
    }
}
