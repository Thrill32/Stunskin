import SwiftUI

private let configEditorHeight: CGFloat = 260

func getPath() -> String { //Reserved on IOS
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false

    if panel.runModal() == .OK {
        return panel.url?.path ?? ""
    }
    return ""
}

func getDirectoryPath() -> String {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false

    if panel.runModal() == .OK {
        return panel.url?.path ?? ""
    }
    return ""
}

func saveTo(content: String, path: String) {
    let allowed = [".conf", ".ovpn"]
    if !allowed.contains(where: { path.hasSuffix($0) }) {
        print("Not a conf file.. dont break things")
        return
    }
    do {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        print("Save failed: \(error)")
    }
}

struct CustomDisclosureView<Content: View>: View {
    @State private var isExpanded = false
    
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            HStack {
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
        }
    }
}

struct SettingsView : View {
    @ObservedObject private var bm : BaseViewModel
    
    init(pbm: BaseViewModel) {
        bm = pbm
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                HStack(spacing: 10) {
                    Text("Stuninstall Quick Setup (Select given folder)")
                    Button("Browse") {
                        DispatchQueue.main.async {
                            let path = getDirectoryPath()
                            bm.fm.readFolder(stunInfoPath: path)
                        }
                    }
                }
                
                CustomDisclosureView(title: "Stunnel") {
                    VStack {
                        HStack(spacing: 10) {
                            TextField("Stunnel .conf Path", text: $bm.curSettings.stunnelPath)
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
                            .frame(height: configEditorHeight)
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3))
                            )
                        Button("Save Conf") {
                            saveTo(content: bm.stunnelConfContent, path: bm.curSettings.stunnelPath)
                        }
                    }
                }
                
                CustomDisclosureView(title: "OpenVPN") {
                    VStack {
                        HStack(spacing: 10) {
                            TextField("OpenVPN .ovpn Path", text: $bm.curSettings.OVPNPath)
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
                            .frame(height: configEditorHeight)
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3))
                            )
                        Button("Save Conf") {
                            saveTo(content: bm.OVPNConfContent, path: bm.curSettings.OVPNPath)
                        }
                    }
                }
                CustomDisclosureView(title: "General Settings") {
                    VStack(spacing: 10) {
                        TextField("Target IP Address", text: $bm.curSettings.targetIP)
                            .textFieldStyle(.roundedBorder)
                        TextField("Target DNS (Separated by commas)", text: Binding(
                            get: { bm.curSettings.DNS.joined(separator: ", ") },
                            set: {
                                bm.curSettings.DNS = $0
                                    .components(separatedBy: ",")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding()
        }
    }
}
