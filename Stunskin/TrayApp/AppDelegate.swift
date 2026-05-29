import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct DaemonState: Decodable {
        let running: Bool
    }

    var statusItem: NSStatusItem!
    var windowController: NSWindowController?
    
    let bm = BaseViewModel.shared //singleton of course
    let dm = BaseViewModel.shared.dm
    
    private var buttonIcon: NSStatusBarButton!
    
    let lockOpenSymbol = "lock.open.fill"
    let lockClosedSymbol = "lock.fill"
    
    private var toggleVPNItem: NSMenuItem!
    private var isVPNRunning = false
    private var stateDirectoryWatcher: DispatchSourceFileSystemObject?
    private var stateDirectoryFileDescriptor: CInt = -1
    
    private let stateDirectoryPath = "/Library/Application Support/Stunskin"
    private let stateFilePath = "/Library/Application Support/Stunskin/daemon-state.json"
    
    private var vpnMenuTitle: String {
        isVPNRunning ? "Disable VPN" : "Enable VPN"
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        refreshVPNState()
        startMonitoringVPNState()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        stopMonitoringVPNState()
    }
    
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
    
    func menuWillOpen(_ menu: NSMenu) {
        refreshVPNState()
    }
    
    private func refreshVPNState() {
        let isRunning = readVPNRunningState()
        
        DispatchQueue.main.async {
            self.isVPNRunning = isRunning
            self.updateStatusUI()
        }
    }
    
    private func readVPNRunningState() -> Bool {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: stateFilePath)),
            let state = try? JSONDecoder().decode(DaemonState.self, from: data)
        else {
            return false
        }
        
        return state.running
    }
    
    private func updateStatusUI() {
        toggleVPNItem?.title = vpnMenuTitle
        buttonIcon?.image = NSImage(
            systemSymbolName: isVPNRunning ? lockClosedSymbol : lockOpenSymbol,
            accessibilityDescription: "Stunskin"
        )
    }
    
    private func startMonitoringVPNState() {
        stopMonitoringVPNState()
        
        stateDirectoryFileDescriptor = open(stateDirectoryPath, O_EVTONLY)
        guard stateDirectoryFileDescriptor >= 0 else { return }
        
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: stateDirectoryFileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        
        watcher.setEventHandler { [weak self] in
            self?.refreshVPNState()
        }
        
        watcher.setCancelHandler { [fileDescriptor = stateDirectoryFileDescriptor] in
            if fileDescriptor >= 0 {
                close(fileDescriptor)
            }
        }
        
        stateDirectoryWatcher = watcher
        watcher.resume()
    }
    
    private func stopMonitoringVPNState() {
        stateDirectoryWatcher?.cancel()
        stateDirectoryWatcher = nil
        stateDirectoryFileDescriptor = -1
    }
    
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
        if isVPNRunning {
            dm.endConnection()
            isVPNRunning = false
        } else {
            dm.initConnection()
            isVPNRunning = true
        }
        
        updateStatusUI()
    }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
