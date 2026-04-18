import SwiftUI

enum WalkFlowWindowID {
    static let main = "main"
}

@main
struct WalkFlowApp: App {
    @StateObject private var controller = WalkingPadController()

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
                Image(systemName: menuBarSymbolName)

                if controller.canControl {
                    Text(controller.speedValueText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbolName: String {
        if controller.isBeltRunning {
            return "figure.walk.motion"
        }

        if controller.canControl {
            return "figure.walk.circle.fill"
        }

        if controller.screenPhase == .connecting {
            return "dot.radiowaves.left.and.right"
        }

        return "figure.walk"
    }
}
