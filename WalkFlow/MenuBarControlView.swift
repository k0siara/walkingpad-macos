import SwiftUI

struct MenuBarControlView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var controller: WalkingPadController

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 14) {
            header

            switch controller.screenPhase {
            case .discovery:
                discoveryContent
            case .connecting:
                connectingContent
            case .connected:
                connectedContent
            }

            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(windowBackground)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WalkFlow")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(inkPrimary)

                Text(controller.activeDeviceName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(inkSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(controller.connectionStatusText)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusTint, in: Capsule())
        }
    }

    private var discoveryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = controller.lastError {
                errorBanner(error)
            }

            Button {
                controller.connectBestCandidate()
            } label: {
                Label("Connect Best", systemImage: "bolt.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(primaryActionTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!controller.canConnectBest)

            HStack(spacing: 10) {
                compactButton(
                    title: controller.isScanning ? "Scanning..." : "Scan",
                    systemImage: "dot.radiowaves.left.and.right",
                    tint: accentBlue,
                    disabled: !controller.canScan,
                    action: controller.startScanningIfPossible
                )

                compactButton(
                    title: "Open App",
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    tint: accentSlate,
                    disabled: false
                ) {
                    openWindow(id: WalkFlowWindowID.main)
                }
            }

            if controller.visibleDevices.isEmpty {
                Text("No treadmill candidates are visible yet.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(surfaceInset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(controller.visibleDevices.prefix(3))) { device in
                        deviceRow(device)
                    }
                }
            }
        }
    }

    private var connectingContent: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)

            Text(controller.detailsText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(inkSecondary)
                .multilineTextAlignment(.center)

            if let error = controller.lastError {
                errorBanner(error)
            }

            compactButton(
                title: "Cancel",
                systemImage: "xmark.circle",
                tint: stopTint,
                disabled: !controller.canCancelConnection,
                action: controller.cancelConnectionAttempt
            )
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private var connectedContent: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text(controller.speedValueText)
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text("km/h")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.72))

                Text(controller.beltSummaryText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.88))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(heroBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack(spacing: 10) {
                stepButton(
                    title: "-0.5",
                    subtitle: "Slower",
                    tint: slowTint,
                    disabled: !controller.canDecreaseSpeed,
                    action: controller.decreaseSpeed
                )

                stepButton(
                    title: "+0.5",
                    subtitle: "Faster",
                    tint: fastTint,
                    disabled: !controller.canIncreaseSpeed,
                    action: controller.increaseSpeed
                )
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(controller.speedPresets, id: \.self) { preset in
                    Button {
                        controller.applySpeedPreset(preset)
                    } label: {
                        VStack(spacing: 2) {
                            Text(WalkingPadProtocol.formatSpeed(preset))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .monospacedDigit()

                            Text("km/h")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(controller.currentSpeedRaw == preset ? Color.white : inkPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            controller.currentSpeedRaw == preset ? accentBlue : Color.white,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(controller.currentSpeedRaw == preset ? Color.white.opacity(0.12) : outlineColor, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!controller.canControl)
                }
            }

            HStack(spacing: 10) {
                Button {
                    controller.stopBelt()
                } label: {
                    actionLabel("STOP", subtitle: "Immediate", tint: stopTint)
                }
                .buttonStyle(.plain)
                .disabled(!controller.canControl)

                Button {
                    controller.startBelt()
                } label: {
                    actionLabel("START", subtitle: "Resume", tint: accentSlate)
                }
                .buttonStyle(.plain)
                .disabled(!controller.canStartBelt)
            }

            HStack(spacing: 8) {
                infoChip(controller.modeText, tint: accentGold)
                infoChip(controller.detailsText, tint: accentSlate, expand: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            compactButton(
                title: "Open App",
                systemImage: "arrow.up.left.and.arrow.down.right",
                tint: accentSlate,
                disabled: false
            ) {
                openWindow(id: WalkFlowWindowID.main)
            }

            compactButton(
                title: "Disconnect",
                systemImage: "bolt.slash",
                tint: stopTint,
                disabled: !controller.canDisconnect,
                action: controller.disconnect
            )
        }
    }

    private var statusTint: Color {
        switch controller.screenPhase {
        case .connected:
            return fastTint
        case .connecting:
            return accentGold
        case .discovery:
            return accentSlate
        }
    }

    private var windowBackground: some View {
        ZStack {
            Color(red: 0.93, green: 0.90, blue: 0.84)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.38),
                    Color(red: 0.83, green: 0.78, blue: 0.70).opacity(0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var cardBackground: Color {
        Color(red: 0.99, green: 0.98, blue: 0.96)
    }

    private var surfaceInset: Color {
        Color(red: 0.95, green: 0.93, blue: 0.89)
    }

    private var outlineColor: Color {
        Color.black.opacity(0.12)
    }

    private var inkPrimary: Color {
        Color(red: 0.11, green: 0.13, blue: 0.17)
    }

    private var inkSecondary: Color {
        Color(red: 0.35, green: 0.37, blue: 0.41)
    }

    private var primaryActionTint: Color {
        Color(red: 0.10, green: 0.27, blue: 0.54)
    }

    private var accentBlue: Color {
        Color(red: 0.15, green: 0.34, blue: 0.68)
    }

    private var accentSlate: Color {
        Color(red: 0.22, green: 0.27, blue: 0.33)
    }

    private var accentGold: Color {
        Color(red: 0.63, green: 0.47, blue: 0.16)
    }

    private var fastTint: Color {
        Color(red: 0.16, green: 0.58, blue: 0.54)
    }

    private var slowTint: Color {
        Color(red: 0.79, green: 0.44, blue: 0.20)
    }

    private var stopTint: Color {
        Color(red: 0.76, green: 0.18, blue: 0.16)
    }

    private var heroBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.14, green: 0.18, blue: 0.24),
                Color(red: 0.09, green: 0.12, blue: 0.17),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func compactButton(
        title: String,
        systemImage: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(disabled ? inkSecondary.opacity(0.55) : tint)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(disabled ? surfaceInset.opacity(0.75) : Color.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(disabled ? outlineColor.opacity(0.5) : tint.opacity(0.42), lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func deviceRow(_ device: WalkingPadDevice) -> some View {
        Button {
            controller.selectedDeviceID = device.id
            controller.connectSelected()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(inkPrimary)
                        .lineLimit(1)

                    Text(signalText(for: device.rssi))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(inkSecondary)
                }

                Spacer()

                if controller.rememberedDeviceID == device.id {
                    Text("Saved")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accentGold)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func stepButton(
        title: String,
        subtitle: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .monospacedDigit()

                Text(subtitle)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(disabled ? Color.white.opacity(0.42) : Color.white)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(disabled ? Color.white.opacity(0.08) : tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func actionLabel(_ title: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .black, design: .rounded))

            Text(subtitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.82))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(.horizontal, 16)
        .background(tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func infoChip(_ text: String, tint: Color, expand: Bool = false) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(expand ? inkPrimary : Color.white)
            .lineLimit(expand ? 2 : 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: expand ? .infinity : nil, alignment: .leading)
            .background(expand ? Color.white : tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(expand ? outlineColor : Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(stopTint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(stopTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(stopTint.opacity(0.24), lineWidth: 1)
            )
    }

    private func signalText(for rssi: Int?) -> String {
        guard let rssi else {
            return "Signal unknown"
        }

        switch rssi {
        case -65...0:
            return "Strong signal"
        case -80 ..< -65:
            return "Medium signal"
        default:
            return "Weak signal"
        }
    }
}
