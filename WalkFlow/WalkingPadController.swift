import Combine
import CoreBluetooth
import Foundation

struct WalkingPadDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let localName: String?
    let advertisedServices: [String]
    let rssi: Int?
    let isLikelyWalkingPad: Bool
    let advertisesKnownWalkingPadService: Bool
    let lastSeen: Date
    let dedupeKey: String
}

struct DebugLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let message: String

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return "\(formatter.string(from: timestamp))  \(message)"
    }
}

enum WalkingPadScreenPhase {
    case discovery
    case connecting
    case connected
}

@MainActor
final class WalkingPadController: NSObject, ObservableObject {
    private enum Preferences {
        static let rememberedDeviceID = "rememberedWalkingPadDeviceID"
        static let rememberedDeviceName = "rememberedWalkingPadDeviceName"
        static let speedPresets = "preferredWalkingPadSpeedPresets"
    }

    private static let defaultSpeedPresets: [UInt8] = [20, 30, 50]
    private static let maximumPresetCount = 5

    @Published private(set) var bluetoothStateText = "Bluetooth is starting..."
    @Published private(set) var isBluetoothReady = false
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredDevices: [WalkingPadDevice] = []
    @Published var selectedDeviceID: UUID?
    @Published private(set) var connectedDeviceID: UUID?
    @Published private(set) var connectionStatusText = "Not connected"
    @Published private(set) var beltSummaryText = "Unknown"
    @Published private(set) var speedText = "-"
    @Published private(set) var modeText = "-"
    @Published private(set) var detailsText = "Scan and connect to a WalkingPad."
    @Published private(set) var lastError: String?
    @Published private(set) var isAutoConnecting = false
    @Published private(set) var debugLog: [DebugLogEntry] = []
    @Published private(set) var rememberedDeviceID: UUID?
    @Published private(set) var rememberedDeviceName: String?
    @Published private(set) var speedPresets: [UInt8] = []

    private var centralManager: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var readCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var commandQueue: [Data] = []
    private var commandPumpTimer: Timer?
    private var statusPollTimer: Timer?
    private var scanTimeoutTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var lastStatus: WalkingPadStatus?
    private var probeQueue: [UUID] = []
    private var pendingConnectionID: UUID?
    private var advanceProbeOnDisconnect = false

    override init() {
        super.init()
        loadRememberedDevice()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    deinit {
        commandPumpTimer?.invalidate()
        statusPollTimer?.invalidate()
        scanTimeoutTask?.cancel()
        connectionTimeoutTask?.cancel()
    }

    var canScan: Bool {
        isBluetoothReady && connectedPeripheral == nil && !isScanning
    }

    var canConnect: Bool {
        isBluetoothReady && selectedDeviceID != nil && connectedPeripheral == nil
            && visibleDevices.contains(where: { $0.id == selectedDeviceID })
    }

    var canConnectBest: Bool {
        isBluetoothReady && !visibleDevices.isEmpty && connectedPeripheral == nil && !isAutoConnecting
    }

    var canDisconnect: Bool {
        connectedPeripheral != nil
    }

    var canCancelConnection: Bool {
        screenPhase == .connecting
    }

    var canControl: Bool {
        connectedPeripheral != nil && writeCharacteristic != nil
    }

    var canStartBelt: Bool {
        canControl && (lastStatus?.isStopped ?? true)
    }

    var canIncreaseSpeed: Bool {
        canControl && currentSpeedRaw < WalkingPadProtocol.maximumSpeedRaw
    }

    var canDecreaseSpeed: Bool {
        canControl && currentSpeedRaw > 0
    }

    var canSaveCurrentSpeedPreset: Bool {
        canControl && currentSpeedRaw > 0 && speedPresets.contains(currentSpeedRaw) == false
    }

    var selectedDeviceName: String {
        guard let selectedDeviceID else {
            return "-"
        }

        return visibleDevices.first(where: { $0.id == selectedDeviceID })?.name
            ?? discoveredDevices.first(where: { $0.id == selectedDeviceID })?.name
            ?? "-"
    }

    var debugLogText: String {
        debugLog.map(\.formatted).joined(separator: "\n")
    }

    var currentSpeedRaw: UInt8 {
        lastStatus?.speed ?? 0
    }

    var speedValueText: String {
        String(format: "%.1f", Double(currentSpeedRaw) / 10.0)
    }

    var screenPhase: WalkingPadScreenPhase {
        if canControl {
            return .connected
        }

        if pendingConnectionID != nil || connectedPeripheral != nil || isAutoConnecting {
            return .connecting
        }

        return .discovery
    }

    var isBeltRunning: Bool {
        !(lastStatus?.isStopped ?? true)
    }

    var startButtonTitle: String {
        isBeltRunning ? "Resume" : "Start"
    }

    var activeDeviceName: String {
        if let connectedDeviceID {
            return visibleDevices.first(where: { $0.id == connectedDeviceID })?.name
                ?? discoveredDevices.first(where: { $0.id == connectedDeviceID })?.name
                ?? rememberedDeviceName
                ?? "WalkingPad"
        }

        if let selectedDeviceID {
            return visibleDevices.first(where: { $0.id == selectedDeviceID })?.name
                ?? discoveredDevices.first(where: { $0.id == selectedDeviceID })?.name
                ?? rememberedDeviceName
                ?? "WalkingPad"
        }

        return rememberedDeviceName ?? "WalkingPad"
    }

    var visibleDevices: [WalkingPadDevice] {
        discoveredDevices.filter { device in
            device.advertisesKnownWalkingPadService
                || device.isLikelyWalkingPad
                || device.id == rememberedDeviceID
        }
    }

    func startScanningIfPossible() {
        guard let centralManager else {
            return
        }

        guard centralManager.state == .poweredOn else {
            updateBluetoothState(centralManager.state)
            return
        }

        appendLog("scan.start")
        lastError = nil
        isScanning = true
        connectionStatusText = "Scanning"
        detailsText = "Looking for WalkingPad devices nearby..."
        discoveredDevices = []
        peripherals = [:]
        selectedDeviceID = nil

        for peripheral in centralManager.retrieveConnectedPeripherals(withServices: WalkingPadProtocol.scanUUIDs) {
            appendLog("scan.retrieveConnected \(describe(peripheral: peripheral))")
            upsert(
                peripheral: peripheral,
                advertisementData: [:],
                rssi: nil,
                forceLikely: true
            )
        }

        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])

        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                self?.stopScanning(reason: "Scan finished")
            }
        }
    }

    func connectSelected() {
        guard let selectedDeviceID else {
            return
        }

        connect(to: selectedDeviceID, autoProbe: false)
    }

    func connectBestCandidate() {
        let candidates = visibleDevices.sorted(by: deviceSortOrder).map(\.id)
        guard !candidates.isEmpty else {
            return
        }

        probeQueue = candidates
        isAutoConnecting = true
        lastError = nil
        connectNextProbeCandidate()
    }

    func disconnect() {
        guard let centralManager, let connectedPeripheral else {
            return
        }

        isAutoConnecting = false
        probeQueue.removeAll()
        connectionStatusText = "Disconnecting"
        detailsText = "Closing Bluetooth connection..."
        centralManager.cancelPeripheralConnection(connectedPeripheral)
    }

    func cancelConnectionAttempt() {
        guard let centralManager else {
            return
        }

        isAutoConnecting = false
        probeQueue.removeAll()
        lastError = nil

        let pendingID = pendingConnectionID
        clearConnectionAttempt()

        if let connectedPeripheral {
            detailsText = "Connection cancelled."
            connectionStatusText = "Disconnected"
            centralManager.cancelPeripheralConnection(connectedPeripheral)
            return
        }

        if let pendingID, let peripheral = peripherals[pendingID] {
            detailsText = "Connection cancelled."
            connectionStatusText = "Disconnected"
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        connectionStatusText = "Not connected"
        detailsText = "Scan and connect to a WalkingPad."
    }

    func startBelt() {
        guard canStartBelt else {
            return
        }

        lastError = nil
        detailsText = "Sending start command..."
        prepareForMotionIfNeeded()
    }

    func stopBelt() {
        guard canControl else {
            return
        }

        lastError = nil
        detailsText = "Sending stop command..."
        removePendingCommands(keys: [1, 4])
        replacePendingCommand(key: 1, with: WalkingPadProtocol.stop())
    }

    func increaseSpeed() {
        adjustSpeed(by: Int(WalkingPadProtocol.speedStepRaw))
    }

    func decreaseSpeed() {
        adjustSpeed(by: -Int(WalkingPadProtocol.speedStepRaw))
    }

    private func enqueue(_ command: Data) {
        commandQueue.append(command)
    }

    private func replacePendingCommand(key: UInt8, with command: Data) {
        commandQueue.removeAll { commandKey(for: $0) == key }
        commandQueue.append(command)
    }

    private func removePendingCommands(keys: Set<UInt8>) {
        commandQueue.removeAll { command in
            guard let key = commandKey(for: command) else {
                return false
            }

            return keys.contains(key)
        }
    }

    private func commandKey(for command: Data) -> UInt8? {
        guard command.count >= 3, command[0] == 0xF7, command[1] == 0xA2 else {
            return nil
        }

        return command[2]
    }

    private func prepareForMotionIfNeeded() {
        if lastStatus?.mode == .sleep || lastStatus == nil {
            replacePendingCommand(key: 2, with: WalkingPadProtocol.setMode(.manual))
        }

        if lastStatus?.isStopped ?? true {
            replacePendingCommand(key: 4, with: WalkingPadProtocol.start())
        }
    }

    private func adjustSpeed(by delta: Int) {
        guard canControl else {
            return
        }

        let current = Int(currentSpeedRaw)
        let target = max(0, min(Int(WalkingPadProtocol.maximumSpeedRaw), current + delta))
        guard target != current else {
            return
        }

        lastError = nil

        if target == 0 {
            stopBelt()
            return
        }

        detailsText = target > current ? "Increasing speed..." : "Reducing speed..."
        prepareForMotionIfNeeded()
        replacePendingCommand(key: 1, with: WalkingPadProtocol.setSpeed(UInt8(target)))
    }

    func applySpeedPreset(_ speed: UInt8) {
        guard canControl else {
            return
        }

        let target = max(1, min(speed, WalkingPadProtocol.maximumSpeedRaw))
        lastError = nil
        detailsText = "Setting speed to \(WalkingPadProtocol.formatSpeed(target)) km/h..."
        prepareForMotionIfNeeded()
        replacePendingCommand(key: 1, with: WalkingPadProtocol.setSpeed(target))
    }

    func saveCurrentSpeedPreset() {
        guard currentSpeedRaw > 0 else {
            return
        }

        speedPresets = normalizeSpeedPresets(speedPresets + [currentSpeedRaw])
        persistSpeedPresets()
        detailsText = "Saved \(WalkingPadProtocol.formatSpeed(currentSpeedRaw)) km/h as a favorite speed."
        appendLog("preset.saved \(WalkingPadProtocol.formatSpeed(currentSpeedRaw))")
    }

    func removeSpeedPreset(_ speed: UInt8) {
        speedPresets.removeAll { $0 == speed }

        if speedPresets.isEmpty {
            speedPresets = Self.defaultSpeedPresets
        }

        persistSpeedPresets()
        detailsText = "Removed \(WalkingPadProtocol.formatSpeed(speed)) km/h preset."
        appendLog("preset.removed \(WalkingPadProtocol.formatSpeed(speed))")
    }

    private func connect(to deviceID: UUID, autoProbe: Bool) {
        guard
            let centralManager,
            let peripheral = peripherals[deviceID]
        else {
            return
        }

        if !autoProbe {
            probeQueue.removeAll()
            isAutoConnecting = false
        }

        advanceProbeOnDisconnect = false
        pendingConnectionID = deviceID
        selectedDeviceID = deviceID
        lastError = nil
        stopScanning(reason: autoProbe ? "Probing candidate..." : "Connecting...")
        connectionStatusText = autoProbe ? "Trying \(displayName(for: peripheral))" : "Connecting to \(displayName(for: peripheral))"
        detailsText = autoProbe ? "Checking whether this device exposes the WalkingPad control service..." : "Discovering BLE services..."
        appendLog("connect.request \(describe(peripheral: peripheral)) autoProbe=\(autoProbe)")
        centralManager.connect(peripheral, options: nil)
        startConnectionTimeout(for: deviceID, autoProbe: autoProbe)
    }

    private func connectNextProbeCandidate() {
        while let nextID = probeQueue.first {
            probeQueue.removeFirst()

            guard peripherals[nextID] != nil else {
                continue
            }

            connect(to: nextID, autoProbe: true)
            return
        }

        isAutoConnecting = false
        connectionStatusText = "No compatible WalkingPad found"
        detailsText = "None of the discovered candidates exposed the expected WalkingPad BLE service."
        appendLog("probe.exhausted")
        if lastError == nil {
            lastError = "The treadmill is visible over BLE, but no candidate exposed service FE00 with FE01/FE02 characteristics."
        }
    }

    private func startConnectionTimeout(for deviceID: UUID, autoProbe: Bool) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))

            await MainActor.run {
                guard
                    let self,
                    self.pendingConnectionID == deviceID,
                    self.writeCharacteristic == nil
                else {
                    return
                }

                let deviceName = self.discoveredDevices.first(where: { $0.id == deviceID })?.name ?? "WalkingPad"

                if autoProbe {
                    self.connectionStatusText = "Candidate timed out"
                    self.detailsText = "\(deviceName) did not finish the BLE handshake in time. Trying next candidate..."
                    self.lastError = nil
                    self.advanceProbeOnDisconnect = true
                    self.appendLog("connect.timeout \(deviceName) autoProbe=true")
                } else {
                    self.connectionStatusText = "Connection timed out"
                    self.detailsText = "The selected device did not finish the BLE handshake in time."
                    self.lastError = "Timed out while connecting to \(deviceName)."
                    self.advanceProbeOnDisconnect = false
                    self.appendLog("connect.timeout \(deviceName) autoProbe=false")
                }

                self.pendingConnectionID = nil

                if let peripheral = self.peripherals[deviceID] {
                    self.centralManager?.cancelPeripheralConnection(peripheral)
                } else if autoProbe {
                    self.connectNextProbeCandidate()
                }
            }
        }
    }

    private func clearConnectionAttempt() {
        pendingConnectionID = nil
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
    }

    private func stopScanning(reason: String) {
        guard let centralManager, isScanning else {
            return
        }

        centralManager.stopScan()
        isScanning = false
        connectionStatusText = reason
        appendLog("scan.stop reason=\(reason)")
    }

    private func beginControlSession() {
        commandPumpTimer?.invalidate()
        statusPollTimer?.invalidate()

        commandPumpTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendNextQueuedCommand()
            }
        }

        statusPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.enqueue(WalkingPadProtocol.queryStatus())
            }
        }

        enqueue(WalkingPadProtocol.queryStatus())
    }

    private func endControlSession() {
        commandQueue.removeAll()
        clearConnectionAttempt()
        commandPumpTimer?.invalidate()
        commandPumpTimer = nil
        statusPollTimer?.invalidate()
        statusPollTimer = nil
        readCharacteristic = nil
        writeCharacteristic = nil
        connectedPeripheral = nil
        connectedDeviceID = nil
        lastStatus = nil
        beltSummaryText = "Unknown"
        speedText = "-"
        modeText = "-"
    }

    private func sendNextQueuedCommand() {
        guard
            let connectedPeripheral,
            let writeCharacteristic,
            !commandQueue.isEmpty
        else {
            return
        }

        let command = commandQueue.removeFirst()
        let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        connectedPeripheral.writeValue(command, for: writeCharacteristic, type: writeType)
    }

    private func updateBluetoothState(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            isBluetoothReady = true
            bluetoothStateText = "Bluetooth ready"
        case .poweredOff:
            isBluetoothReady = false
            bluetoothStateText = "Bluetooth is turned off"
        case .unauthorized:
            isBluetoothReady = false
            bluetoothStateText = "Bluetooth permission denied"
        case .unsupported:
            isBluetoothReady = false
            bluetoothStateText = "Bluetooth LE is unsupported on this Mac"
        case .resetting:
            isBluetoothReady = false
            bluetoothStateText = "Bluetooth is resetting..."
        case .unknown:
            fallthrough
        @unknown default:
            isBluetoothReady = false
            bluetoothStateText = "Bluetooth state is unknown"
        }
    }

    private func isLikelyWalkingPad(
        peripheral: CBPeripheral,
        advertisementData: [String: Any]
    ) -> Bool {
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = (peripheral.name ?? localName ?? "").lowercased()

        return advertisedServices.contains(WalkingPadProtocol.serviceUUID)
            || advertisedServices.contains(WalkingPadProtocol.vendorServiceUUID)
            || advertisedServices.contains(WalkingPadProtocol.vendorSecondaryUUID)
            || name.contains("walkingpad")
            || name.contains("kingsmith")
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        peripheral.name ?? "WalkingPad"
    }

    private func loadRememberedDevice() {
        let defaults = UserDefaults.standard
        if let rawID = defaults.string(forKey: Preferences.rememberedDeviceID) {
            rememberedDeviceID = UUID(uuidString: rawID)
        }
        rememberedDeviceName = defaults.string(forKey: Preferences.rememberedDeviceName)
        loadSpeedPresets()
    }

    private func rememberDevice(id: UUID, name: String) {
        rememberedDeviceID = id
        rememberedDeviceName = name

        let defaults = UserDefaults.standard
        defaults.set(id.uuidString, forKey: Preferences.rememberedDeviceID)
        defaults.set(name, forKey: Preferences.rememberedDeviceName)

        appendLog("device.remembered \(name) [\(id.uuidString)]")
    }

    private func loadSpeedPresets() {
        let defaults = UserDefaults.standard
        let storedPresets = defaults.array(forKey: Preferences.speedPresets) as? [Int] ?? []
        speedPresets = normalizeSpeedPresets(storedPresets.compactMap { UInt8(exactly: $0) })

        if speedPresets.isEmpty {
            speedPresets = Self.defaultSpeedPresets
            persistSpeedPresets()
        }
    }

    private func persistSpeedPresets() {
        UserDefaults.standard.set(speedPresets.map(Int.init), forKey: Preferences.speedPresets)
    }

    private func normalizeSpeedPresets(_ presets: [UInt8]) -> [UInt8] {
        Array(Set(presets.filter { $0 > 0 && $0 <= WalkingPadProtocol.maximumSpeedRaw }))
            .sorted()
            .prefix(Self.maximumPresetCount)
            .map { $0 }
    }

    private func upsert(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber?,
        forceLikely: Bool = false
    ) {
        peripherals[peripheral.identifier] = peripheral
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
            .sorted()
        let normalizedRSSI = Self.normalize(rssi: rssi?.intValue)
        let advertisesKnownService = advertisedServices.contains(WalkingPadProtocol.serviceUUID.uuidString)
            || advertisedServices.contains(WalkingPadProtocol.vendorServiceUUID.uuidString)
            || advertisedServices.contains(WalkingPadProtocol.vendorSecondaryUUID.uuidString)
        let likely = forceLikely || isLikelyWalkingPad(peripheral: peripheral, advertisementData: advertisementData)
        let dedupeKey = makeDedupeKey(
            name: displayName(for: peripheral),
            localName: localName,
            advertisedServices: advertisedServices
        )

        let device = WalkingPadDevice(
            id: peripheral.identifier,
            name: displayName(for: peripheral),
            localName: localName,
            advertisedServices: advertisedServices,
            rssi: normalizedRSSI,
            isLikelyWalkingPad: likely,
            advertisesKnownWalkingPadService: advertisesKnownService,
            lastSeen: Date(),
            dedupeKey: dedupeKey
        )

        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else if let index = discoveredDevices.firstIndex(where: { $0.dedupeKey == dedupeKey }) {
            discoveredDevices[index] = preferredDevice(lhs: discoveredDevices[index], rhs: device)
        } else {
            discoveredDevices.append(device)
        }

        discoveredDevices.sort(by: deviceSortOrder)

        if selectedDeviceID == nil {
            selectedDeviceID = visibleDevices.first?.id
        } else if visibleDevices.contains(where: { $0.id == selectedDeviceID }) == false {
            selectedDeviceID = visibleDevices.first?.id
        }

        detailsText = "Found \(visibleDevices.count) treadmill candidate(s)"
    }

    private func deviceSortOrder(_ lhs: WalkingPadDevice, _ rhs: WalkingPadDevice) -> Bool {
        let lhsRemembered = lhs.id == rememberedDeviceID
        let rhsRemembered = rhs.id == rememberedDeviceID
        if lhsRemembered != rhsRemembered {
            return lhsRemembered && !rhsRemembered
        }

        if lhs.advertisesKnownWalkingPadService != rhs.advertisesKnownWalkingPadService {
            return lhs.advertisesKnownWalkingPadService && !rhs.advertisesKnownWalkingPadService
        }

        if lhs.isLikelyWalkingPad != rhs.isLikelyWalkingPad {
            return lhs.isLikelyWalkingPad && !rhs.isLikelyWalkingPad
        }

        let lhsRSSI = lhs.rssi ?? Int.min
        let rhsRSSI = rhs.rssi ?? Int.min
        if lhsRSSI != rhsRSSI {
            return lhsRSSI > rhsRSSI
        }

        if lhs.lastSeen != rhs.lastSeen {
            return lhs.lastSeen > rhs.lastSeen
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func preferredDevice(lhs: WalkingPadDevice, rhs: WalkingPadDevice) -> WalkingPadDevice {
        if deviceSortOrder(lhs, rhs) {
            return lhs
        }

        return rhs
    }

    private func makeDedupeKey(
        name: String,
        localName: String?,
        advertisedServices: [String]
    ) -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedLocalName = (localName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let servicesKey = advertisedServices.joined(separator: "|").lowercased()

        if servicesKey.isEmpty {
            return "\(normalizedName)|\(normalizedLocalName)"
        }

        return "\(normalizedName)|\(normalizedLocalName)|\(servicesKey)"
    }

    private static func normalize(rssi: Int?) -> Int? {
        guard let rssi else {
            return nil
        }

        // CoreBluetooth may report 127 when RSSI is not available.
        guard rssi != 127 else {
            return nil
        }

        return rssi
    }

    private func handleStatusUpdate(_ status: WalkingPadStatus) {
        lastStatus = status
        beltSummaryText = status.beltSummary
        speedText = status.speedText
        modeText = status.modeText
        detailsText = status.isStopped ? "Belt is ready" : "Belt is moving"
        appendLog("notify.status state=\(status.state) speed=\(status.speed) mode=\(status.mode?.rawValue ?? 255)")
    }

    func clearDebugLog() {
        debugLog.removeAll()
        appendLog("log.cleared")
    }

    private func appendLog(_ message: String) {
        debugLog.append(DebugLogEntry(timestamp: Date(), message: message))
        if debugLog.count > 200 {
            debugLog.removeFirst(debugLog.count - 200)
        }
    }

    private func describe(peripheral: CBPeripheral) -> String {
        let name = displayName(for: peripheral)
        return "\(name) [\(peripheral.identifier.uuidString)]"
    }
}

extension WalkingPadController: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            self?.updateBluetoothState(central.state)
            self?.appendLog("central.state \(central.state.rawValue)")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.upsert(
                peripheral: peripheral,
                advertisementData: advertisementData,
                rssi: RSSI
            )
            let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString).joined(separator: ",")
            let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "-"
            self.appendLog("scan.discover \(self.describe(peripheral: peripheral)) rssi=\(RSSI.intValue) localName=\(localName) services=[\(services)]")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.clearConnectionAttempt()
            self.appendLog("connect.didConnect \(self.describe(peripheral: peripheral))")
            self.connectedPeripheral = peripheral
            self.connectedDeviceID = peripheral.identifier
            self.connectionStatusText = self.isAutoConnecting ? "Probing \(self.displayName(for: peripheral))" : "Connected to \(self.displayName(for: peripheral))"
            self.detailsText = "Discovering BLE services..."
            peripheral.delegate = self
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.clearConnectionAttempt()
            self.lastError = error?.localizedDescription ?? "Failed to connect to the selected device."
            self.connectionStatusText = "Connection failed"
            self.detailsText = "Make sure the official WalkingPad app is closed."
            self.appendLog("connect.didFail \(self.describe(peripheral: peripheral)) error=\(self.lastError ?? "-")")

            if self.isAutoConnecting {
                self.connectNextProbeCandidate()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let shouldContinueProbe = self.isAutoConnecting && !self.probeQueue.isEmpty
            let shouldAdvanceAfterDisconnect = self.advanceProbeOnDisconnect
            self.advanceProbeOnDisconnect = false
            self.appendLog("connect.didDisconnect \(self.describe(peripheral: peripheral)) error=\(error?.localizedDescription ?? "-")")
            self.endControlSession()
            self.connectionStatusText = shouldContinueProbe ? "Trying next candidate" : "Disconnected"
            self.detailsText = shouldContinueProbe ? "Previous candidate was not a compatible WalkingPad treadmill." : "Connection closed"
            if let error {
                self.lastError = error.localizedDescription
            }

            if self.isAutoConnecting && shouldAdvanceAfterDisconnect {
                self.connectNextProbeCandidate()
            }
        }
    }
}

extension WalkingPadController: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if let error {
                self.lastError = error.localizedDescription
                self.connectionStatusText = "Service discovery failed"
                self.appendLog("service.error \(self.describe(peripheral: peripheral)) error=\(error.localizedDescription)")
                if self.isAutoConnecting {
                    self.advanceProbeOnDisconnect = true
                    self.centralManager?.cancelPeripheralConnection(peripheral)
                }
                return
            }

            let services = peripheral.services?.map(\.uuid.uuidString).joined(separator: ",") ?? ""
            self.appendLog("service.list \(self.describe(peripheral: peripheral)) services=[\(services)]")
            guard let service = peripheral.services?.first(where: { $0.uuid == WalkingPadProtocol.serviceUUID }) else {
                if self.isAutoConnecting {
                    self.lastError = nil
                    self.connectionStatusText = "Candidate rejected"
                    self.detailsText = "\(self.displayName(for: peripheral)) has no FE00 service. Trying next candidate..."
                    self.appendLog("service.missingFE00 \(self.describe(peripheral: peripheral))")
                    self.advanceProbeOnDisconnect = true
                    self.centralManager?.cancelPeripheralConnection(peripheral)
                } else {
                    self.lastError = "WalkingPad service FE00 was not found on this device."
                    self.connectionStatusText = "Unsupported device"
                    self.appendLog("service.missingFE00 \(self.describe(peripheral: peripheral)) manual")
                }
                return
            }

            self.detailsText = "Discovering FE01 / FE02 characteristics..."
            self.appendLog("service.foundFE00 \(self.describe(peripheral: peripheral))")
            peripheral.discoverCharacteristics([WalkingPadProtocol.readUUID, WalkingPadProtocol.writeUUID], for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if let error {
                self.lastError = error.localizedDescription
                self.connectionStatusText = "Characteristic discovery failed"
                self.appendLog("characteristics.error \(self.describe(peripheral: peripheral)) error=\(error.localizedDescription)")
                if self.isAutoConnecting {
                    self.advanceProbeOnDisconnect = true
                    self.centralManager?.cancelPeripheralConnection(peripheral)
                }
                return
            }

            let chars = service.characteristics?.map(\.uuid.uuidString).joined(separator: ",") ?? ""
            self.appendLog("characteristics.list \(self.describe(peripheral: peripheral)) chars=[\(chars)]")
            for characteristic in service.characteristics ?? [] {
                switch characteristic.uuid {
                case WalkingPadProtocol.readUUID:
                    self.readCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                case WalkingPadProtocol.writeUUID:
                    self.writeCharacteristic = characteristic
                default:
                    break
                }
            }

            guard self.readCharacteristic != nil, self.writeCharacteristic != nil else {
                if self.isAutoConnecting {
                    self.lastError = nil
                    self.connectionStatusText = "Candidate rejected"
                    self.detailsText = "\(self.displayName(for: peripheral)) has no FE01/FE02 pair. Trying next candidate..."
                    self.appendLog("characteristics.missingPair \(self.describe(peripheral: peripheral))")
                    self.advanceProbeOnDisconnect = true
                    self.centralManager?.cancelPeripheralConnection(peripheral)
                } else {
                    self.lastError = "WalkingPad control characteristics were not found."
                    self.connectionStatusText = "Unsupported device"
                    self.appendLog("characteristics.missingPair \(self.describe(peripheral: peripheral)) manual")
                }
                return
            }

            self.clearConnectionAttempt()
            self.isAutoConnecting = false
            self.probeQueue.removeAll()
            self.rememberDevice(id: peripheral.identifier, name: self.displayName(for: peripheral))
            self.connectionStatusText = "Ready"
            self.detailsText = "Control channel established"
            self.appendLog("characteristics.ready \(self.describe(peripheral: peripheral))")
            self.beginControlSession()
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            if let error {
                self?.lastError = error.localizedDescription
                self?.appendLog("notify.stateError \(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
            } else {
                self?.appendLog("notify.state \(characteristic.uuid.uuidString) isNotifying=\(characteristic.isNotifying)")
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if let error {
                self.lastError = error.localizedDescription
                self.appendLog("notify.error \(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
                return
            }

            guard
                characteristic.uuid == WalkingPadProtocol.readUUID,
                let value = characteristic.value,
                let status = WalkingPadProtocol.parseStatus(from: value)
            else {
                let hex = characteristic.value?.map { String(format: "%02X", $0) }.joined() ?? "-"
                self.appendLog("notify.raw \(characteristic.uuid.uuidString) payload=\(hex)")
                return
            }

            self.handleStatusUpdate(status)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            if let error {
                self?.lastError = error.localizedDescription
                self?.appendLog("write.error \(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
            } else {
                self?.appendLog("write.ok \(characteristic.uuid.uuidString)")
            }
        }
    }
}
