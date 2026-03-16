import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var windowController: NSWindowController?
    
    let bm = BaseViewModel.shared //singleton of course
    let dm = BaseViewModel.shared.dm
    
    private var buttonIcon: NSStatusBarButton!
    
    let lockOpenSymbol = "lock.open.fill"
    let lockClosedSymbol = "lock.fill"
    
    private var toggleVPNItem: NSMenuItem!
    
    private var vpnMenuTitle: String {
        dm.isInit ? "Disable VPN" : "Enable VPN"
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            buttonIcon = button
            button.image = NSImage(systemSymbolName: lockOpenSymbol, accessibilityDescription: "Stunskin")

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
        toggleVPNItem.title = vpnMenuTitle
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
    
    @objc func toggleVPN() { //checks status on menu open so should be well updated for user
        if (dm.isInit) {
            dm.endConnection()
            buttonIcon.image = NSImage(systemSymbolName: lockOpenSymbol, accessibilityDescription: "Stunskin")
        } else {
            dm.initConnection()
            buttonIcon.image = NSImage(systemSymbolName: lockClosedSymbol, accessibilityDescription: "Stunskin")
        }
    }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

