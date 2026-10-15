import Foundation
import CorkKit

func bottleSettingsTests() -> [TestCase] {
    [
        TestCase(name: "defaults", body: {
            let settings = BottleSettings()
            try expect(settings.windowsVersion == .win10)
            try expect(settings.backend == .dxmt)
            try expect(settings.msync)
        }),
        TestCase(name: "applyValidKeys", body: {
            var settings = BottleSettings()
            try settings.apply(key: "windows", value: "win7")
            try settings.apply(key: "backend", value: "dxvk")
            try settings.apply(key: "msync", value: "false")
            try settings.apply(key: "metal-hud", value: "on")

            try expect(settings.windowsVersion == .win7)
            try expect(settings.backend == .dxvk)
            try expect(settings.msync == false)
            try expect(settings.metalHUD)
        }),
        TestCase(name: "applyRejectsBadValues", body: {
            var settings = BottleSettings()
            try expectThrows(CorkError.self) { try settings.apply(key: "windows", value: "windows95") }
            try expectThrows(CorkError.self) { try settings.apply(key: "backend", value: "opengl") }
            try expectThrows(CorkError.self) { try settings.apply(key: "msync", value: "maybe") }
            try expectThrows(CorkError.self) { try settings.apply(key: "nonsense", value: "1") }
        }),
        TestCase(name: "roundTripCoding", body: {
            var settings = BottleSettings()
            try settings.apply(key: "backend", value: "dxvk")
            try settings.apply(key: "dxvk-hud", value: "fps,devinfo")

            let data = try JSONEncoder.cork.encode(settings)
            let decoded = try JSONDecoder.cork.decode(BottleSettings.self, from: data)
            try expect(decoded == settings)
            try expectEqual(decoded.dxvkHUD, "fps,devinfo")
        }),
        TestCase(name: "backendOverrides", body: {
            try expect(GraphicsBackend.wined3d.wineDLLOverrides == nil)
            try expectEqual(GraphicsBackend.dxvk.wineDLLOverrides, "dxgi,d3d9,d3d10core,d3d11=n,b")
            try expect(GraphicsBackend.dxmt.wineDLLOverrides == nil)
            try expect(GraphicsBackend.dxmt.usesBuiltinLibraryPath)
            try expect(GraphicsBackend.dxvk.usesBuiltinLibraryPath == false)
        }),
        TestCase(name: "windowsVersionRegistryMapping", body: {
            try expectEqual(WindowsVersion.win10.registryVersion, "10.0")
            try expectEqual(WindowsVersion.win7.registryVersion, "6.1")
            try expectEqual(WindowsVersion.win81.registryBuild, "9600")
        }),
        TestCase(name: "backendFromName", body: {
            try expect(GraphicsBackend(rawValue: "dxmt") == .dxmt)
            try expect(GraphicsBackend(rawValue: "dxvk") == .dxvk)
            try expect(GraphicsBackend(rawValue: "wined3d") == .wined3d)
            try expect(GraphicsBackend(rawValue: "metal") == nil)
        }),
    ]
}
