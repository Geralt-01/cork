import ArgumentParser
import CorkEngine
import CorkKit
import Foundation

/// Shared CLI helpers.
func locateCatalog(explicit: String?) throws -> URL {
    if let explicit {
        let url = URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("No catalog at \(url.path)")
        }
        return url
    }
    if let detected = CrossOverData.defaultTieURL() {
        return detected
    }
    throw ValidationError("No catalog specified. Pass --catalog /path/to/crossover.tie")
}
