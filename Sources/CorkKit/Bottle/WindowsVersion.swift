import Foundation

public enum WindowsVersion: String, Codable, Sendable, CaseIterable {
    case win7
    case win8
    case win81
    case win10

    public var displayName: String {
        switch self {
        case .win7: return "Windows 7"
        case .win8: return "Windows 8"
        case .win81: return "Windows 8.1"
        case .win10: return "Windows 10"
        }
    }

    public var registryVersion: String {
        switch self {
        case .win7: return "6.1"
        case .win8: return "6.2"
        case .win81: return "6.3"
        case .win10: return "10.0"
        }
    }

    public var registryBuild: String {
        switch self {
        case .win7: return "7601"
        case .win8: return "9200"
        case .win81: return "9600"
        case .win10: return "19045"
        }
    }
}
