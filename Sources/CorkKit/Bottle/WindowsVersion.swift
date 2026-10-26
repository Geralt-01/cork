import Foundation

/// A Windows version a bottle reports to the programs inside it.
///
/// CrossTie recipes (`<installerwinver>`) and bottles commonly ask for these
/// versions, so Cork supports the full range Wine can emulate — not just the
/// modern ones — otherwise recipes for older apps fail to apply their version.
public enum WindowsVersion: String, Codable, Sendable, CaseIterable {
    case win95
    case win98
    case winme
    case nt40
    case win2000
    case winxp
    case win2003
    case winvista
    case win2008
    case win7
    case win8
    case win81
    case win10

    public var displayName: String {
        switch self {
        case .win95: return "Windows 95"
        case .win98: return "Windows 98"
        case .winme: return "Windows ME"
        case .nt40: return "Windows NT 4.0"
        case .win2000: return "Windows 2000"
        case .winxp: return "Windows XP"
        case .win2003: return "Windows Server 2003"
        case .winvista: return "Windows Vista"
        case .win2008: return "Windows Server 2008"
        case .win7: return "Windows 7"
        case .win8: return "Windows 8"
        case .win81: return "Windows 8.1"
        case .win10: return "Windows 10"
        }
    }

    /// The value Wine itself uses for this version (e.g. `winecfg /v <value>`).
    public var wineVersion: String { rawValue }

    /// `CurrentVersion` written to
    /// `HKLM\Software\Microsoft\Windows NT\CurrentVersion`.
    public var registryVersion: String {
        switch self {
        case .win95: return "4.0"
        case .win98: return "4.10"
        case .winme: return "4.90"
        case .nt40: return "4.0"
        case .win2000: return "5.0"
        case .winxp: return "5.1"
        case .win2003: return "5.2"
        case .winvista: return "6.0"
        case .win2008: return "6.0"
        case .win7: return "6.1"
        case .win8: return "6.2"
        case .win81: return "6.3"
        case .win10: return "10.0"
        }
    }

    /// `CurrentBuildNumber` written alongside ``registryVersion``.
    public var registryBuild: String {
        switch self {
        case .win95: return "950"
        case .win98: return "1998"
        case .winme: return "3000"
        case .nt40: return "1381"
        case .win2000: return "2195"
        case .winxp: return "2600"
        case .win2003: return "3790"
        case .winvista: return "6002"
        case .win2008: return "6002"
        case .win7: return "7601"
        case .win8: return "9200"
        case .win81: return "9600"
        case .win10: return "19045"
        }
    }

    /// `CurrentMajorVersionNumber` (DWORD). Wine reports this value in
    /// preference to `CurrentVersion` for Windows 8.1 and newer, so it must be
    /// kept in sync when switching a prefix's reported version.
    public var registryMajor: Int {
        switch self {
        case .win95, .win98, .winme, .nt40: return 4
        case .win2000, .winxp, .win2003: return 5
        case .winvista, .win2008, .win7, .win8, .win81: return 6
        case .win10: return 10
        }
    }

    /// `CurrentMinorVersionNumber` (DWORD), paired with ``registryMajor``.
    public var registryMinor: Int {
        switch self {
        case .win95: return 0
        case .win98: return 10
        case .winme: return 90
        case .nt40, .win2000: return 0
        case .winxp: return 1
        case .win2003: return 2
        case .winvista, .win2008: return 0
        case .win7: return 1
        case .win8: return 2
        case .win81: return 3
        case .win10: return 0
        }
    }

    /// Parses a version written by a user or a CrossTie recipe, accepting the
    /// common aliases (`win2k`, `w2k3`, `vista`, `winxp64`, …).
    public init?(catalogValue value: String) {
        let needle = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = WindowsVersion(rawValue: needle) {
            self = exact
            return
        }
        switch needle {
        case "win2k", "w2k", "win2000pro": self = .win2000
        case "win2k3", "w2k3", "win2003r2": self = .win2003
        case "vista": self = .winvista
        case "win2008r2", "win2k8": self = .win2008
        case "winxp64", "winxpx64", "winxpsp2", "winxpsp3": self = .winxp
        case "win95osr2": self = .win95
        case "win98se": self = .win98
        case "windows7": self = .win7
        case "windows8": self = .win8
        case "windows8.1", "win8.1": self = .win81
        case "windows10": self = .win10
        case "nt4": self = .nt40
        default: return nil
        }
    }
}
