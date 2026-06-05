import Cocoa
import SwiftUI
import notify

class VPNStateObserver {
    
    private var tokens: [Int32] = []
    
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onConnecting: (() -> Void)?
    var onFailed: (() -> Void)?
    
    func startListening() {
        observe("com.stunskin.vpn.connected")    { [weak self] in self?.onConnected?() }
        observe("com.stunskin.vpn.disconnected") { [weak self] in self?.onDisconnected?() }
        observe("com.stunskin.vpn.connecting")   { [weak self] in self?.onConnecting?() }
        observe("com.stunskin.vpn.disconnecting"){ }
        observe("com.stunskin.vpn.failed")    { [weak self] in self?.onFailed?() }
    }
    
    func stopListening() {
        tokens.forEach { notify_cancel($0) }
        tokens.removeAll()
    }
    
    private func observe(_ name: String, handler: @escaping () -> Void) {
        var token: Int32 = 0
        notify_register_dispatch(name, &token, .main) { _ in
            handler()
        }
        tokens.append(token)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct DaemonState: Decodable {
        let running: Bool
    }
    
    let observer = VPNStateObserver()
    
    var statusItem: NSStatusItem!
    var windowController: NSWindowController?
    
    let bm = BaseViewModel.shared //singleton of course
    let dm = BaseViewModel.shared.dm
    
    private var buttonIcon: NSStatusBarButton!
    
    let lockOpenSymbol = "lock.open.fill"
    let lockClosedSymbol = "lock.fill"
    let pendingSymbol = "arrow.trianglehead.clockwise.rotate.90"
    
    private var toggleVPNItem: NSMenuItem!
    private var VPNStatus = 0 // 0 OFF | 1 CONNECTING | 2 ON
    private var stateDirectoryWatcher: DispatchSourceFileSystemObject?
    private var stateDirectoryFileDescriptor: CInt = -1
    
    private let stateDirectoryPath = "/Library/Application Support/Stunskin/Data"
    private let stateFilePath = "/Library/Application Support/Stunskin/Data/daemon-state.json"
    
    private var vpnMenuTitle: String {
        switch VPNStatus {
        case 0:
            return "Enable VPN"
        case 2:
            return "Disable VPN"
        case 1:
            return "Connecting..."
        case -1:
            return "Connection Failed"
        default:
            return "Unknown Status"
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        observer.onConnected = { [weak self] in
            
            DispatchQueue.main.async {
                self?.VPNStatus = 2
                self?.updateStatusUI()
            }
        }
        
        observer.onDisconnected = { [weak self] in
            DispatchQueue.main.async {
                self?.VPNStatus = 0
                self?.updateStatusUI()
            }
        }
        
        observer.onConnecting = { [weak self] in
            DispatchQueue.main.async {
                self?.VPNStatus = 1
                self?.updateStatusUI()
            }
        }
        
        observer.onFailed = { [weak self] in
            DispatchQueue.main.async {
                self?.VPNStatus = -1
                self?.updateStatusUI()
            }
        }
        
        observer.startListening()
        
        dm.manager.client.connect()
        dm.manager.client.isRunning { [weak self] running in
            DispatchQueue.main.async {
                self?.VPNStatus = running ? 2 : 0
                self?.updateStatusUI()
            }
        }
        
        setupStatusItem()
//        refreshVPNState()
//        startMonitoringVPNState()
    }
    
//    func applicationWillTerminate(_ notification: Notification) {
//        stopMonitoringVPNState()
//    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            buttonIcon = button
            updateStatusUI()
        }

        statusItem.menu = buildMenu()
    }
    
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
    
        menu.delegate = self
        
        let titleItem = NSMenuItem(title: "Stunskin", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())
        
        toggleVPNItem = NSMenuItem(
            title: vpnMenuTitle,
            action: #selector(toggleVPN),
            keyEquivalent: "v"
        )
        menu.addItem(toggleVPNItem)
        
        menu.addItem(NSMenuItem(
            title: "Open Stunskin",
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        ))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "About Stunskin",
            action: #selector(showAbout),
            keyEquivalent: ""
        ))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit Stunskin",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        for item in menu.items {
            if item.action != #selector(NSApplication.terminate(_:)) {
                item.target = self
            }
        }

        return menu
    }
    
//    func menuWillOpen(_ menu: NSMenu) {
//        refreshVPNState()
//    }
    
//    private func refreshVPNState() {
//        let isRunning = readVPNRunningState()
//        
//        DispatchQueue.main.async {
//            self.isVPNRunning = isRunning
//            self.updateStatusUI()
//        }
//    }
    
//    private func readVPNRunningState() -> Bool {
//        guard
//            let data = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath)),
//            let state = try? JSONDecoder().decode(DaemonState.self, from: data)
//        else {
//            return false
//        }
//        
//        return state.running
//    }
    
    private func updateStatusUI() {
        toggleVPNItem?.title = vpnMenuTitle
        
        var imageName = ""
        
        switch VPNStatus {
        case 0:
            imageName = lockOpenSymbol
        case 2:
            imageName = lockClosedSymbol
        case 1:
            imageName = pendingSymbol
        case -1:
            imageName = "lock.open.trianglebadge.exclamationmark.fill"
        default:
            imageName = lockOpenSymbol
        }
        buttonIcon?.image = NSImage(
            systemSymbolName: imageName,
                
//                isVPNRunning ? lockClosedSymbol : lockOpenSymbol,
            accessibilityDescription: "Stunskin"
        )
    }
    
//    private func startMonitoringVPNState() {
//        stopMonitoringVPNState()
//        
//        stateDirectoryFileDescriptor = open(stateDirectoryPath, O_EVTONLY)
//        guard stateDirectoryFileDescriptor >= 0 else { return }
//        
//        let watcher = DispatchSource.makeFileSystemObjectSource(
//            fileDescriptor: stateDirectoryFileDescriptor,
//            eventMask: [.write, .delete, .rename],
//            queue: DispatchQueue.global(qos: .utility)
//        )
//        
//        watcher.setEventHandler { [weak self] in
//            self?.refreshVPNState()
//        }
//        
//        watcher.setCancelHandler { [fileDescriptor = stateDirectoryFileDescriptor] in
//            if fileDescriptor >= 0 {
//                close(fileDescriptor)
//            }
//        }
//        
//        stateDirectoryWatcher = watcher
//        watcher.resume()
//    }
//    
//    private func stopMonitoringVPNState() {
//        stateDirectoryWatcher?.cancel()
//        stateDirectoryWatcher = nil
//        stateDirectoryFileDescriptor = -1
//    }
    
    @objc func openMainWindow() {
        if windowController == nil {
            let contentView = ContentView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Stunskin"
            window.contentView = NSHostingView(rootView: contentView)
            window.center()
            window.setFrameAutosaveName("MainWindow")
            windowController = NSWindowController(window: window)
        }

        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func toggleVPN() {
        if VPNStatus == 2 {
            dm.endConnection()
        } else {
            // Use the new init path that sends configs via XPC and start showing Connecting immediately
            dm.newInitConnection()
            VPNStatus = 1
        }
        
        updateStatusUI()
    }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

