import AppKit
import SwiftUI

enum WalkFlowWindowID {
    static let main = "main"
}

@main
struct WalkFlowApp: App {
    @StateObject private var controller = WalkingPadController()
    private let menuBarIcon = WalkFlowApp.makeMenuBarIcon()

    init() {
        NSApplication.shared.applicationIconImage = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some Scene {
        WindowGroup("WalkFlow", id: WalkFlowWindowID.main) {
            ContentView()
                .environmentObject(controller)
        }

        MenuBarExtra {
            MenuBarControlView()
                .environmentObject(controller)
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: menuBarIcon)
                    .renderingMode(.original)

                if controller.canControl {
                    Text(controller.speedValueText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private static func makeMenuBarIcon() -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }
}
