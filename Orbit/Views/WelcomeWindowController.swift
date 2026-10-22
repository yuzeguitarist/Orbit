
import AppKit
import SwiftUI

final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()
    
    private init() {
        let welcomeView = WelcomeView()
        let hostingView = NSHostingView(rootView: welcomeView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.backgroundColor = NSColor.windowBackgroundColor
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }
}
