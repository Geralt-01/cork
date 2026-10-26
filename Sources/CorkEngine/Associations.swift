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
/// Associations are persisted in a Cork-owned JSON file inside the bottle
/// (`<bottle>/cork-associations.json`), which is the authoritative record. On
/// every write Cork also best-effort mirrors them into the bottle's Wine
/// registry so Windows programs honour them; if the bottle or runtime is
/// unavailable the change is still persisted (a warning is emitted).
///
/// NOTE: frozen CorkEngine API surface.
public struct AssociationStore: Sendable {
    /// Name of the Cork-owned file inside the bottle directory.
    public static let fileName = "cork-associations.json"

    public let paths: CorkPaths

    /// Whether `write`/`set`/`remove` mirror changes into the Wine registry.
    /// The JSON file is always written regardless. Disable in tests and
    /// headless edits that must not touch a prefix.
    public let appliesRegistry: Bool

    public init(paths: CorkPaths = .resolve()) {
        self.init(paths: paths, appliesRegistry: true)
    }

    /// - Parameter appliesRegistry: set `false` to only manage the JSON file.
    public init(paths: CorkPaths, appliesRegistry: Bool) {
        self.paths = paths
        self.appliesRegistry = appliesRegistry
    }

    /// Location of the Cork-owned association file for a bottle.
    public func fileURL(bottle: String) -> URL {
        paths.bottleDirectory(named: bottle).appendingPathComponent(Self.fileName)
    }

    /// All associations currently configured for a bottle.
    ///
    /// Never throws on a missing or corrupt file: both yield an empty list so
    /// callers can treat "no associations" and "unreadable file" alike.
    public func read(bottle: String) throws -> [AssociationEntry] {
        try Bottle.validateName(bottle)
        let url = fileURL(bottle: bottle)
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let file = try? JSONDecoder.cork.decode(AssociationFile.self, from: data) else {
            return []
        }
        return file.entries.normalizedAssociations()
    }

    /// Replace the association set for a bottle.
    ///
    /// Entries are canonicalised, de-duplicated and sorted, then written
    /// atomically. Registry application is best-effort.
    public func write(bottle: String, entries: [AssociationEntry]) throws {
        try Bottle.validateName(bottle)
        let previous = (try? read(bottle: bottle)) ?? []
        let normalized = entries.normalizedAssociations()
        let url = fileURL(bottle: bottle)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let file = AssociationFile(entries: normalized)
        try JSONEncoder.cork.encode(file).write(to: url, options: .atomic)
        applyToWineRegistry(bottle: bottle, entries: normalized, previous: previous)
    }

    /// Add/replace a single association.
    public func set(_ entry: AssociationEntry, bottle: String) throws {
        var entries = try read(bottle: bottle)
        var normalized = entry
        normalized.fileExtension = AssociationEntry.normalizeExtension(entry.fileExtension)
        entries.removeAll { $0.fileExtension == normalized.fileExtension }
        entries.append(normalized)
        try write(bottle: bottle, entries: entries)
    }

    /// Remove an association by extension. Removing an unknown extension is a
    /// no-op, so the operation is idempotent.
    public func remove(fileExtension: String, bottle: String) throws {
        let ext = AssociationEntry.normalizeExtension(fileExtension)
        var entries = try read(bottle: bottle)
        let before = entries.count
        entries.removeAll { $0.fileExtension == ext }
        guard entries.count != before else { return }
        try write(bottle: bottle, entries: entries)
    }

    /// The `wine reg …` lines that would be applied for a bottle's
    /// associations. Useful for inspection without a runtime installed.
    public func registryCommandLines(bottle: String) throws -> [String] {
        AssociationRegistry.commandLines(for: try read(bottle: bottle))
    }

    /// Sync bottle associations into a bundle's `CFBundleDocumentTypes`, so the
    /// generated `.app` registers for those file types on macOS.
    ///
    /// - Returns: the extensions that were registered, with dot, sorted.
    /// - Throws: ``CorkError/fileSystem(reason:)`` if the bundle has no
    ///   readable/parseable `Contents/Info.plist`.
    public func registerInBundle(_ bundleURL: URL, bottle: String) throws -> [String] {
        let entries = try read(bottle: bottle)
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")

        guard let data = try? Data(contentsOf: infoURL) else {
            throw CorkError.fileSystem(
                reason: "cannot read bundle Info.plist at \(infoURL.path)"
            )
        }
        guard let plist = (try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )) as? [String: Any] else {
            throw CorkError.fileSystem(
                reason: "bundle Info.plist is not a property-list dictionary: \(infoURL.path)"
            )
        }

        let merged = BundleDocumentTypes.applying(entries, to: plist)
        guard !merged.extensions.isEmpty else { return [] }

        let output = try PropertyListSerialization.data(
            fromPropertyList: merged.plist, format: .xml, options: 0
        )
        try output.write(to: infoURL, options: .atomic)
        return merged.extensions
    }

    // MARK: - Wine registry

    /// Best-effort registry application. Never throws: the JSON file is the
    /// source of truth, so a missing bottle or runtime only warns.
    private func applyToWineRegistry(
        bottle: String,
        entries: [AssociationEntry],
        previous: [AssociationEntry]
    ) {
        guard appliesRegistry else { return }
        guard FileManager.default.fileExists(atPath: paths.bottleDirectory(named: bottle).path) else {
            warn("bottle '\(bottle)' not found; associations saved but not applied to the registry")
            return
        }

        let manager: BottleManager
        do {
            manager = try BottleManager(paths: paths)
        } catch {
            warn("could not open bottle '\(bottle)' (\(describe(error))); associations saved only")
            return
        }
        guard manager.runtime.isWineReady else {
            warn("Wine runtime not installed; associations saved but not applied to the registry")
            return
        }

        // Remove stale mappings first: an extension that has been unassigned and
        // any ProgID no longer referenced by a remaining entry.
        let currentProgIDs = Set(entries.map(\.progID))
        let removedProgIDs = Set(previous.map(\.progID)).subtracting(currentProgIDs)
        let currentExtensions = Set(entries.map(\.fileExtension))
        let removedExtensions = Set(previous.map(\.fileExtension)).subtracting(currentExtensions)
        let removals = AssociationRegistry.removalCommands(
            progIDs: removedProgIDs,
            fileExtensions: removedExtensions
        )
        for arguments in removals {
            do {
                _ = try manager.exec(named: bottle, command: "reg", arguments: arguments)
            } catch {
                warn("could not remove stale association registry key: \(describe(error))")
                break
            }
        }

        for entry in entries {
            for arguments in AssociationRegistry.commands(for: entry) {
                do {
                    _ = try manager.exec(named: bottle, command: "reg", arguments: arguments)
                } catch {
                    warn("could not apply \(entry.fileExtension) association: \(describe(error))")
                    return
                }
            }
        }
    }

    private func warn(_ message: String) {
        FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
    }

    private func describe(_ error: Error) -> String {
        if let corkError = error as? CorkError {
            return corkError.errorDescription ?? "\(corkError)"
        }
        return "\(error)"
    }
}
