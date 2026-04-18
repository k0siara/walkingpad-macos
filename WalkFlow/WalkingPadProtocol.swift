import CoreBluetooth
import Foundation

enum WalkingPadMode: UInt8 {
    case automatic = 0
    case manual = 1
    case sleep = 2

    var description: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .manual:
            return "Manual"
        case .sleep:
            return "Sleep"
        }
    }
}

struct WalkingPadStatus {
    let state: UInt8
    let speed: UInt8
    let mode: WalkingPadMode?

    var isStopped: Bool {
        state == 0 || state == 5 || speed == 0
    }

    var beltSummary: String {
        switch state {
        case 0, 5:
            return "Stopped"
        case 1:
            return "Running"
        default:
            return "State \(state)"
        }
    }

    var speedText: String {
        "\(WalkingPadProtocol.formatSpeed(speed)) km/h"
    }

    var modeText: String {
        mode?.description ?? "Unknown"
    }
}

enum WalkingPadProtocol {
    static let serviceUUID = CBUUID(string: "FE00")
    static let readUUID = CBUUID(string: "FE01")
    static let writeUUID = CBUUID(string: "FE02")
    static let vendorServiceUUID = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0D1912")
    static let vendorSecondaryUUID = CBUUID(string: "00010203-0405-0607-0809-0A0B0C0D2B12")
    static let genericAccessUUID = CBUUID(string: "1800")
    static let deviceInformationUUID = CBUUID(string: "180A")
    static let speedStepRaw: UInt8 = 5
    static let maximumSpeedRaw: UInt8 = 120

    static let scanUUIDs: [CBUUID] = [
        serviceUUID,
        vendorServiceUUID,
        vendorSecondaryUUID,
        genericAccessUUID,
        deviceInformationUUID,
    ]

    static func queryStatus() -> Data {
        messageByte(key: 0, value: 0)
    }

    static func setSpeed(_ speed: UInt8) -> Data {
        messageByte(key: 1, value: speed)
    }

    static func setMode(_ mode: WalkingPadMode) -> Data {
        messageByte(key: 2, value: mode.rawValue)
    }

    static func start() -> Data {
        messageByte(key: 4, value: 1)
    }

    static func stop() -> Data {
        setSpeed(0)
    }

    static func formatSpeed(_ rawSpeed: UInt8) -> String {
        String(format: "%.1f", Double(rawSpeed) / 10.0)
    }

    static func parseStatus(from data: Data) -> WalkingPadStatus? {
        let bytes = [UInt8](data)

        guard bytes.count >= 15, bytes[1] == 0xA2 else {
            return nil
        }

        return WalkingPadStatus(
            state: bytes[2],
            speed: bytes[3],
            mode: WalkingPadMode(rawValue: bytes[4])
        )
    }

    private static func messageByte(key: UInt8, value: UInt8) -> Data {
        let checksum = 0xA2 &+ key &+ value
        return Data([0xF7, 0xA2, key, value, checksum, 0xFD])
    }
}
