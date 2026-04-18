import AppKit
import SwiftUI

struct ContentView: View {
    @AppStorage("showWalkFlowDebugLog") private var showDebugLog = false
    @EnvironmentObject private var controller: WalkingPadController

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 16) {
                    header

                    switch controller.screenPhase {
                    case .discovery:
                        discoveryScreen
                    case .connecting:
                        connectingScreen
                    case .connected:
                        controlScreen
                    }

                    if controller.screenPhase != .connecting {
                        debugPanel
                    }
                }
                .frame(maxWidth: 920)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 940, minHeight: 700)
        .onAppear {
            controller.startScanningIfPossible()
        }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.90, green: 0.87, blue: 0.81)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(red: 0.68, green: 0.77, blue: 0.90).opacity(0.34),
                    Color.clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.40),
                    Color(red: 0.85, green: 0.80, blue: 0.72).opacity(0.22),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WalkFlow")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(controller.activeDeviceName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
            }

            Spacer()

            headerChip(
                text: controller.bluetoothStateText,
                tint: controller.isBluetoothReady ? Color.teal : Color.red
            )

            if let rememberedDeviceName = controller.rememberedDeviceName {
                headerChip(
                    text: "Remembered: \(rememberedDeviceName)",
                    tint: Color.orange
                )
            }

            if controller.screenPhase == .connected {
                Button("Disconnect") {
                    controller.disconnect()
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(Color.white)
                .background(Color(red: 0.73, green: 0.20, blue: 0.17), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .disabled(!controller.canDisconnect)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.18, blue: 0.24),
                    Color(red: 0.09, green: 0.12, blue: 0.17),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 20, x: 0, y: 12)
    }

    private var discoveryScreen: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ready to connect")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(inkPrimary)

                    Text("Pick the treadmill once, then the main flow should always start from the remembered device.")
                        .font(.headline)
                        .foregroundStyle(inkSecondary)
                }

                if let error = controller.lastError {
                    errorBanner(error)
                }

                Button {
                    controller.connectBestCandidate()
                } label: {
                    mainActionLabel(
                        title: "Connect Best",
                        subtitle: "Use the best treadmill candidate nearby",
                        systemImage: "bolt.fill"
                    )
                }
                .buttonStyle(.plain)
                .disabled(!controller.canConnectBest)

                HStack(spacing: 12) {
                    secondaryButton(
                        title: controller.isScanning ? "Scanning..." : "Scan",
                        systemImage: "dot.radiowaves.left.and.right",
                        tint: Color.blue,
                        disabled: !controller.canScan,
                        action: controller.startScanningIfPossible
                    )

                    secondaryButton(
                        title: "Connect Selected",
                        systemImage: "link",
                        tint: Color.gray,
                        disabled: !controller.canConnect,
                        action: controller.connectSelected
                    )
                }
            }
            .padding(24)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 22, x: 0, y: 12)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Available Treadmills")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(inkPrimary)

                    Spacer()

                    Text("\(controller.visibleDevices.count)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(inkSecondary)
                }

                if controller.visibleDevices.isEmpty {
                    Text("No treadmill candidates are visible yet. Wake the belt, close the official app, and scan again.")
                        .font(.headline)
                        .foregroundStyle(inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 10) {
                        ForEach(controller.visibleDevices) { device in
                            discoveryDeviceRow(device)
                        }
                    }
                }
            }
            .padding(22)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 10)
        }
    }

    private var connectingScreen: some View {
        VStack(spacing: 16) {
            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.2)

                Text(controller.connectionStatusText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text(controller.activeDeviceName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(inkSecondary)

                Text(controller.detailsText)
                    .font(.headline)
                    .foregroundStyle(inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                if let error = controller.lastError {
                    errorBanner(error)
                        .frame(maxWidth: 520)
                }

                secondaryButton(
                    title: "Cancel",
                    systemImage: "xmark.circle",
                    tint: Color.red,
                    disabled: !controller.canCancelConnection,
                    action: controller.cancelConnectionAttempt
                )
                .frame(maxWidth: 220)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 34)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 22, x: 0, y: 12)
        }
    }

    private var controlScreen: some View {
        VStack(spacing: 16) {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(controller.activeDeviceName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)

                        Text(controller.connectionStatusText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }

                    Spacer()

                    statusBadge(controller.modeText, tint: Color.white.opacity(0.12), foreground: Color.white)
                }

                VStack(spacing: 6) {
                    Text("Current Speed")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.74))

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(controller.speedValueText)
                            .font(.system(size: 108, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                            .contentTransition(.numericText())

                        Text("km/h")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }

                    Text(controller.beltSummaryText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.92))
                }

                HStack(spacing: 16) {
                    speedStepButton(
                        title: "-0.5",
                        subtitle: "Slower",
                        tint: Color(red: 0.83, green: 0.45, blue: 0.22),
                        disabled: !controller.canDecreaseSpeed,
                        action: controller.decreaseSpeed
                    )

                    speedStepButton(
                        title: "+0.5",
                        subtitle: "Faster",
                        tint: Color(red: 0.17, green: 0.63, blue: 0.43),
                        disabled: !controller.canIncreaseSpeed,
                        action: controller.increaseSpeed
                    )
                }
            }
            .padding(26)
            .background(heroBackground, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

            favoritePresetsSection

            HStack(spacing: 14) {
                actionButton(
                    title: "STOP",
                    subtitle: "Immediate stop",
                    tint: Color(red: 0.81, green: 0.21, blue: 0.16),
                    foreground: Color.white,
                    disabled: !controller.canControl,
                    action: controller.stopBelt
                )

                actionButton(
                    title: "START",
                    subtitle: "Start belt",
                    tint: Color(red: 0.15, green: 0.23, blue: 0.28),
                    foreground: Color.white,
                    disabled: !controller.canStartBelt,
                    action: controller.startBelt
                )
                .frame(maxWidth: 240)
            }

            compactStatusBlock

            if let error = controller.lastError {
                errorBanner(error)
            }
        }
    }

    private var favoritePresetsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Favorite Speeds")
                        .font(.title3.weight(.bold))

                    Text("One press to jump to a preferred pace.")
                        .font(.headline)
                        .foregroundStyle(inkSecondary)
                }

                Spacer()

                Button {
                    controller.saveCurrentSpeedPreset()
                } label: {
                    Label("Save Current", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(inkPrimary)
                        .background(Color(red: 0.95, green: 0.84, blue: 0.63), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 0.72, green: 0.51, blue: 0.20).opacity(0.42), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!controller.canSaveCurrentSpeedPreset)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(controller.speedPresets, id: \.self) { preset in
                        favoritePresetButton(preset)
                    }
                }
            }
        }
        .padding(22)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 10)
    }

    private var compactStatusBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                statusBadge(controller.connectionStatusText, tint: Color(red: 0.16, green: 0.58, blue: 0.54), foreground: Color.white)
                statusBadge(controller.beltSummaryText, tint: Color(red: 0.22, green: 0.27, blue: 0.33), foreground: Color.white)
                statusBadge(controller.modeText, tint: Color(red: 0.63, green: 0.47, blue: 0.16), foreground: Color.white)
            }

            Text(controller.detailsText)
                .font(.headline)
                .foregroundStyle(inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 10)
    }

    private var debugPanel: some View {
        DisclosureGroup(isExpanded: $showDebugLog) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()

                    Button("Copy Log") {
                        copyDebugLog()
                    }
                    .disabled(controller.debugLog.isEmpty)

                    Button("Clear Log") {
                        controller.clearDebugLog()
                    }
                    .disabled(controller.debugLog.isEmpty)
                }

                ScrollView {
                    Text(controller.debugLogText.isEmpty ? "No BLE events yet." : controller.debugLogText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(minHeight: 170)
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Label("Show Debug", systemImage: "ladybug")
                    .font(.headline.weight(.semibold))

                Spacer()

                Text("\(controller.debugLog.count) entries")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(inkSecondary)
            }
        }
        .padding(18)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 10)
    }

    private var cardBackground: Color {
        Color(red: 0.99, green: 0.98, blue: 0.96)
    }

    private var outlineColor: Color {
        Color.black.opacity(0.12)
    }

    private var insetSurfaceBackground: Color {
        Color(red: 0.95, green: 0.93, blue: 0.89)
    }

    private var inkPrimary: Color {
        Color(red: 0.11, green: 0.13, blue: 0.17)
    }

    private var inkSecondary: Color {
        Color(red: 0.35, green: 0.37, blue: 0.41)
    }

    private var heroBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.11, green: 0.13, blue: 0.16),
                Color(red: 0.17, green: 0.20, blue: 0.25),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func headerChip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.28), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.55), lineWidth: 1)
            )
    }

    private func statusBadge(_ text: String, tint: Color, foreground: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint, in: Capsule())
    }

    private func mainActionLabel(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .heavy))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))

                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.8))
            }

            Spacer()
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.36, blue: 0.68),
                    Color(red: 0.08, green: 0.18, blue: 0.34),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.08, green: 0.18, blue: 0.34).opacity(0.26), radius: 18, x: 0, y: 10)
    }

    private func secondaryButton(
        title: String,
        systemImage: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(disabled ? inkSecondary.opacity(0.55) : tint)
                .background(disabled ? insetSurfaceBackground.opacity(0.65) : Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(disabled ? outlineColor.opacity(0.55) : tint.opacity(0.46), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .shadow(color: disabled ? Color.clear : Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
    }

    private func discoveryDeviceRow(_ device: WalkingPadDevice) -> some View {
        let selected = controller.selectedDeviceID == device.id

        return Button {
            controller.selectedDeviceID = device.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(inkPrimary)

                    HStack(spacing: 8) {
                        if controller.rememberedDeviceID == device.id {
                            smallBadge("Remembered", tint: Color.orange)
                        }

                        if device.advertisesKnownWalkingPadService {
                            smallBadge("FE00", tint: Color.teal)
                        }

                        smallBadge(signalLabel(for: device.rssi), tint: Color.gray, foreground: inkSecondary)
                    }
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(red: 0.15, green: 0.34, blue: 0.68))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color(red: 0.15, green: 0.34, blue: 0.68).opacity(0.15) : insetSurfaceBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? Color(red: 0.15, green: 0.34, blue: 0.68).opacity(0.55) : outlineColor, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func speedStepButton(
        title: String,
        subtitle: String,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .monospacedDigit()

                Text(subtitle)
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(disabled ? Color.white.opacity(0.45) : Color.white)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(disabled ? Color.white.opacity(0.06) : tint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(disabled ? 0.06 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func actionButton(
        title: String,
        subtitle: String,
        tint: Color,
        foreground: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 30, weight: .black, design: .rounded))

                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(disabled ? inkSecondary : foreground.opacity(0.82))
            }
            .foregroundStyle(disabled ? inkSecondary : foreground)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .padding(.horizontal, 22)
            .background(disabled ? insetSurfaceBackground : tint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(disabled ? outlineColor.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .shadow(color: disabled ? Color.clear : Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
    }

    private func favoritePresetButton(_ preset: UInt8) -> some View {
        let isCurrent = controller.currentSpeedRaw == preset

        return Button {
            controller.applySpeedPreset(preset)
        } label: {
            VStack(spacing: 4) {
                Text(WalkingPadProtocol.formatSpeed(preset))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("km/h")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCurrent ? Color.white.opacity(0.78) : inkSecondary)
            }
            .foregroundStyle(isCurrent ? Color.white : inkPrimary)
            .frame(width: 128)
            .frame(minHeight: 90)
            .background(
                isCurrent ? Color(red: 0.14, green: 0.22, blue: 0.34) : Color.white,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isCurrent ? Color.white.opacity(0.10) : outlineColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!controller.canControl)
        .shadow(color: isCurrent ? Color.black.opacity(0.16) : Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
        .contextMenu {
            Button("Remove Preset") {
                controller.removeSpeedPreset(preset)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.red)

            Text(message)
                .font(.headline)
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.20), lineWidth: 1)
        )
    }

    private func smallBadge(_ text: String, tint: Color, foreground: Color? = nil) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(foreground ?? tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.26), lineWidth: 1)
            )
    }

    private func signalLabel(for rssi: Int?) -> String {
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

    private func copyDebugLog() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(controller.debugLogText, forType: .string)
    }
}
