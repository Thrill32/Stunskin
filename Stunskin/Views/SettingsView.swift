import SwiftUI

private let configEditorHeight: CGFloat = 260

func getPath() -> String {
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
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
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
    
    @State private var showingDeleteConfirmation = false
    @State private var selectedProfile = "stunskinprofile-DEFAULT.json"
    @State private var isRevertingProfile = false
    
    //TODO: Possibly save last-used profile name in userdata. Perhaps unnecessary
    
    
    @State private var profileSaveName = ""
    
    init(pbm: BaseViewModel) {
        bm = pbm
    }
    
    @State private var profiles: [String] = ["stunskinprofile-DEFAULT.json"]
    
    var body: some View {
        ScrollView {
            
            VStack(spacing: 15) {
                HStack(spacing: 10) {
                    Picker("Profile", selection: $selectedProfile) {
                        ForEach(profiles, id: \.self) { profile in
                            Text(ProfileManager.simplifyProfileName(profile))
                                .tag(profile)
                        }
                    }
                    .onHover { isHovering in
                        guard isHovering else { return }
                        
                        do {
                            if let newProfiles = try ProfileManager.scanProfiles(path: ProfileManager.corePath.path) {
                                profiles = newProfiles
                            }
                            print("Selprof: " + selectedProfile)
                            print("ProfSN: " + profileSaveName)
                        } catch {
                            print("An error occurred: \(error)")
                        }
                    }
                    .onChange(of: selectedProfile) { oldValue, newValue in
                        if isRevertingProfile {
                            isRevertingProfile = false
                            return
                        }
                        selectedProfile = newValue
                        profileSaveName = ProfileManager.simplifyProfileName(newValue)
                        do {
                            print("Attempt load: " + newValue)
                            let newSettings = try ProfileManager.loadState(
                                path:ProfileManager.simpleToURL(ProfileManager.simplifyProfileName(newValue)).path
                            )
                            bm.curSettings.targetIP = newSettings.targetIP
                            bm.curSettings.stunnelPath = newSettings.stunnelPath
                            bm.curSettings.OVPNPath = newSettings.OVPNPath
                            bm.curSettings.DNS = newSettings.DNS
                            
                            bm.stunnelConfContent = bm.readConf(path: newSettings.stunnelPath)
                            bm.OVPNConfContent = bm.readConf(path: newSettings.OVPNPath)
                        } catch {
                            print("An error occurred: \(error)")
                            isRevertingProfile = true
                            selectedProfile = oldValue
                        }
                    }
                    
                    TextField("Profile Name", text: $profileSaveName, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .padding(0)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3))
                        ).onChange(of: profileSaveName) { oldValue, newValue in
                            profileSaveName = newValue
                            //TODO: verify this
                        }
                    Button("Save") {
                        //logic to save/make new profile
                        
                        ProfileManager.saveState(path: ProfileManager.simpleToURL(profileSaveName).path, currentData: bm.curSettings)
                    }
                    
                    Button("Delete") {
                        showingDeleteConfirmation = true
                    }
                    .confirmationDialog(
                        "Are you sure you want to delete this profile?",
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Yes") {
                            showingDeleteConfirmation = false
                            ProfileManager.deleteProfile(path: ProfileManager.simpleToURL(profileSaveName))
                            print("Deleting Fired: " + ProfileManager.simpleToURL(profileSaveName).path)
                        }
                        Button("No", role: .cancel) {
                            showingDeleteConfirmation = false
                        }
                    } message: {
                        Text("This action cannot be undone.")
                    }
                }
                
                
                HStack(spacing: 10) {
                    Text("Stuninstall Quick Setup (Select the Folder)")
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
