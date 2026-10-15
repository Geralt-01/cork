import Foundation

public enum CorkError: Error, LocalizedError {
    case runtimeNotInstalled
    case componentUnknown(id: String)
    case componentNotInstalled(id: String, version: String)
    case manifestMissing
    case manifestInvalid(String)
    case downloadFailed(url: String, underlying: String)
    case downloadSizeMismatch(expected: Int, actual: Int)
    case checksumMismatch(expected: String, actual: String)
    case archiveUnsafe(reason: String)
    case extractionFailed(reason: String)
    case wineBinaryMissing(path: String)
    case bottleNotFound(name: String)
    case bottleAlreadyExists(name: String)
    case invalidBottleName(name: String)
    case invalidSetting(String)
    case processFailed(command: String, status: Int32)
    case fileSystem(reason: String)
    case rosettaMissing
    case unsupported(reason: String)

    public var errorDescription: String? {
        switch self {
        case .runtimeNotInstalled:
            return "No Wine runtime is installed."
        case .componentUnknown(let id):
            return "Unknown runtime component '\(id)'."
        case .componentNotInstalled(let id, let version):
            return "Component '\(id)' version \(version) is not installed."
        case .manifestMissing:
            return "The bundled runtime manifest could not be found."
        case .manifestInvalid(let reason):
            return "The runtime manifest is invalid: \(reason)"
        case .downloadFailed(let url, let underlying):
            return "Failed to download \(url): \(underlying)"
        case .downloadSizeMismatch(let expected, let actual):
            return "Downloaded \(actual) bytes but expected \(expected)."
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch.\n  expected: \(expected)\n  actual:   \(actual)"
        case .archiveUnsafe(let reason):
            return "Refusing to extract an unsafe archive: \(reason)"
        case .extractionFailed(let reason):
            return "Extraction failed: \(reason)"
        case .wineBinaryMissing(let path):
            return "The Wine runtime is incomplete; missing \(path)."
        case .bottleNotFound(let name):
            return "Bottle '\(name)' does not exist."
        case .bottleAlreadyExists(let name):
            return "A bottle named '\(name)' already exists."
        case .invalidBottleName(let name):
            return "Invalid bottle name '\(name)'."
        case .invalidSetting(let reason):
            return "Invalid setting: \(reason)"
        case .processFailed(let command, let status):
            return "Command failed with exit code \(status): \(command)"
        case .fileSystem(let reason):
            return "Filesystem error: \(reason)"
        case .rosettaMissing:
            return "Rosetta 2 is not installed."
        case .unsupported(let reason):
            return "Unsupported: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .runtimeNotInstalled:
            return "Run 'cork runtime install' to download and set up the Wine runtime."
        case .componentNotInstalled:
            return "Run 'cork runtime install' to install the missing component."
        case .checksumMismatch:
            return "The download may be corrupted or tampered with. Delete it and retry."
        case .rosettaMissing:
            return "Install it with: softwareupdate --install-rosetta --agree-to-license"
        case .wineBinaryMissing:
            return "Reinstall the runtime with 'cork runtime install --force'."
        default:
            return nil
        }
    }
}
