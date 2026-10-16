import Foundation

public struct BottleSettings: Codable, Sendable, Equatable {
    public var windowsVersion: WindowsVersion
    public var backend: GraphicsBackend
    public var msync: Bool
    public var esync: Bool
    public var dxvkAsync: Bool
    public var metalHUD: Bool
    public var dxvkHUD: String?
    public var debugChannels: String

    public init(
        windowsVersion: WindowsVersion = .win10,
        backend: GraphicsBackend = .dxmt,
        msync: Bool = true,
        esync: Bool = true,
        dxvkAsync: Bool = true,
        metalHUD: Bool = false,
        dxvkHUD: String? = nil,
        debugChannels: String = "fixme-all"
    ) {
        self.windowsVersion = windowsVersion
        self.backend = backend
        self.msync = msync
        self.esync = esync
        self.dxvkAsync = dxvkAsync
        self.metalHUD = metalHUD
        self.dxvkHUD = dxvkHUD
        self.debugChannels = debugChannels
    }

    public enum Key: String, CaseIterable {
        case windows
        case backend
        case msync
        case esync
        case dxvkAsync = "dxvk-async"
        case metalHud = "metal-hud"
        case dxvkHud = "dxvk-hud"
        case debug = "debug"
    }

    public mutating func apply(key: String, value: String) throws {
        guard let key = Key(rawValue: key) else {
            throw CorkError.invalidSetting("unknown key '\(key)' (expected one of \(Key.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        switch key {
        case .windows:
            guard let version = WindowsVersion(catalogValue: value) else {
                throw CorkError.invalidSetting("windows must be one of \(WindowsVersion.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            windowsVersion = version
        case .backend:
            guard let backend = GraphicsBackend(rawValue: value.lowercased()) else {
                throw CorkError.invalidSetting("backend must be one of \(GraphicsBackend.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            self.backend = backend
        case .msync:
            msync = try Self.parseBool(value)
        case .esync:
            esync = try Self.parseBool(value)
        case .dxvkAsync:
            dxvkAsync = try Self.parseBool(value)
        case .metalHud:
            metalHUD = try Self.parseBool(value)
        case .dxvkHud:
            dxvkHUD = value == "off" ? nil : value
        case .debug:
            debugChannels = value == "off" ? "" : value
        }
    }

    static func parseBool(_ value: String) throws -> Bool {
        switch value.lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: throw CorkError.invalidSetting("expected a boolean, got '\(value)'")
        }
    }
}
