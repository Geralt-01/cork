import CorkKit
import Foundation

/// A file-type association inside a bottle: extension → Windows program.
///
/// NOTE: frozen CorkEngine API surface.
public struct AssociationEntry: Sendable, Hashable, Codable {
    /// File extension including the dot, e.g. `.psd`.
    public var fileExtension: String
    /// Windows ProgID, e.g. `Photoshop.Image.12`.
    public var progID: String
    /// Friendly name shown to the user.
    public var friendlyName: String?
    /// Windows path of the program that opens this type.
    public var executable: String
    /// Optional extra arguments.
    public var arguments: [String]

    public init(
        fileExtension: String,
        progID: String,
        friendlyName: String? = nil,
        executable: String,
        arguments: [String] = []
    ) {
        self.fileExtension = fileExtension
        self.progID = progID
        self.friendlyName = friendlyName
        self.executable = executable
        self.arguments = arguments
    }
}

/// Reads/writes bottle file associations (the equivalent of CrossOver's
/// `cxassoc.conf`), so Windows programs can be opened for Mac file types.
///
/// NOTE: frozen CorkEngine API surface.
public struct AssociationStore: Sendable {
    public let paths: CorkPaths

    public init(paths: CorkPaths = .resolve()) {
        self.paths = paths
    }

    /// All associations currently configured for a bottle.
    public func read(bottle: String) throws -> [AssociationEntry] {
        _ = bottle
        return []
    }

    /// Replace the association set for a bottle.
    public func write(bottle: String, entries: [AssociationEntry]) throws {
        _ = (bottle, entries)
        throw CorkError.unsupported(reason: "file associations are not implemented yet")
    }

    /// Add/replace a single association.
    public func set(_ entry: AssociationEntry, bottle: String) throws {
        _ = (entry, bottle)
        throw CorkError.unsupported(reason: "file associations are not implemented yet")
    }

    /// Remove an association by extension.
    public func remove(fileExtension: String, bottle: String) throws {
        _ = (fileExtension, bottle)
        throw CorkError.unsupported(reason: "file associations are not implemented yet")
    }

    /// Sync bottle associations into a bundle's `CFBundleDocumentTypes`, so the
    /// generated `.app` registers for those file types on macOS.
    ///
    /// TODO(assoc): implement; return the extensions that were registered.
    public func registerInBundle(_ bundleURL: URL, bottle: String) throws -> [String] {
        _ = (bundleURL, bottle)
        return []
    }
}
