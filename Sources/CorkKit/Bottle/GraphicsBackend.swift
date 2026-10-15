import Foundation

public enum GraphicsBackend: String, Codable, Sendable, CaseIterable {
    case wined3d
    case dxvk
    case dxmt

    public var displayName: String {
        switch self {
        case .wined3d: return "WineD3D"
        case .dxvk: return "DXVK (Vulkan)"
        case .dxmt: return "DXMT (Metal)"
        }
    }

    public var summary: String {
        switch self {
        case .wined3d:
            return "Wine's built-in Direct3D implementation. No extra components; best for older or simple titles."
        case .dxvk:
            return "Direct3D 9/10/11 translated to Vulkan via MoltenVK. Great compatibility for D3D9/10/11 games."
        case .dxmt:
            return "Direct3D 10/11 translated directly to Metal. Best performance and compatibility for modern D3D11 titles."
        }
    }

    public var wineDLLOverrides: String? {
        switch self {
        case .wined3d:
            return nil
        case .dxvk:
            return "dxgi,d3d9,d3d10core,d3d11=n,b"
        case .dxmt:
            return nil
        }
    }

    public var requiresComponentID: String? {
        switch self {
        case .wined3d: return nil
        case .dxvk: return "dxvk"
        case .dxmt: return "dxmt"
        }
    }

    public var usesBuiltinLibraryPath: Bool {
        self == .dxmt
    }
}
