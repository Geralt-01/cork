import Foundation

public enum WineEnvironment {
    public static func launchEnvironment(
        bottle: Bottle,
        installation: WineInstallation,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = installation.baseEnvironment(patching: base)
        environment["WINEPREFIX"] = bottle.url.path

        let settings = bottle.settings
        environment["WINEDEBUG"] = settings.debugChannels.isEmpty ? "-all" : settings.debugChannels

        // Bottle settings are authoritative: do not let variables inherited
        // from the user's shell (or a previous backend) leak into the run.
        environment.removeValue(forKey: "WINEDLLOVERRIDES")
        environment.removeValue(forKey: "DXVK_ASYNC")
        environment.removeValue(forKey: "DXVK_HUD")
        environment.removeValue(forKey: "MTL_HUD_ENABLED")
        environment.removeValue(forKey: "WINEMSYNC")
        environment.removeValue(forKey: "WINEESYNC")

        if settings.msync { environment["WINEMSYNC"] = "1" }
        if settings.esync { environment["WINEESYNC"] = "1" }

        if let overrides = settings.backend.wineDLLOverrides {
            environment["WINEDLLOVERRIDES"] = overrides
        }

        switch settings.backend {
        case .dxvk:
            environment["DXVK_ASYNC"] = settings.dxvkAsync ? "1" : "0"
            if let hud = settings.dxvkHUD { environment["DXVK_HUD"] = hud }
        case .dxmt:
            if settings.metalHUD { environment["MTL_HUD_ENABLED"] = "1" }
            if settings.backend.usesBuiltinLibraryPath {
                environment["WINEDLLPATH"] = "\(bottle.graphicsDirectory.path):\(installation.libDirectory.path)"
            }
        case .wined3d:
            break
        }

        return environment
    }
}
