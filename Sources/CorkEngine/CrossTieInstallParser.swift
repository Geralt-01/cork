import Foundation

// MARK: - Extraction model
//
// These types are *internal* to `CorkEngine`. Only `CrossTieInstallRecipes`
// (the frozen, public entry point) is exposed to callers; this file owns the
// mapping from the loosely-documented CrossTie XML to `InstallStep`s.
//
// Shape notes learned from a real `crossover.tie` (CrossOver 24/25):
//
// * Download metadata lives in `<appprofile>`:
//   `<downloadurl>`, `<downloadurl64>`, `<downloadglob>`, `<downloadpageurl>`.
// * Installer execution metadata lives in `<installprofile>`:
//   `<installerwinver>`, `<installerdlloverrides>`, `<installersilentoption>`,
//   `<installeroption>`, `<installerglob>`, `<localinstallerglob>`,
//   `<preinstallregistry>`/`<postinstallregistry>`, `<filestocopy>`,
//   `<lnkfile>`, `<preinstallenvironment>`/`<installerenvironment>`,
//   `<postinstallreboot>`, `<postinstallurl>`, `<selfextract*>`.
// * `<app>` records repeat per `<cxversion>`; install data is unioned across
//   them (scalars: later record wins, collections: deduped union).
// * `<appprofile><installerid>` references *another* app whose recipe provides
//   the installer (e.g. Microsoft Word 2000 → Microsoft Office 2000). It is
//   resolved lazily by `CrossTieInstallRecipes`.

/// A registry value to write, tagged with whether it runs before or after the
/// installer. `name`/`data` may be empty (some recipes only create a key).
struct CrossTieRegistryEntry: Sendable, Hashable {
    var isPreInstall: Bool
    var key: String
    var name: String
    var data: String
}

/// A `<filestocopy>` entry: `<glob>` (source) → `<dst>` (destination).
struct CrossTieFileCopy: Sendable, Hashable {
    var source: String
    var destination: String
}

/// A `<lnkfile>` shortcut description, pre-resolved into the field layout the
/// frozen `InstallStep` (and the install-b `ShortcutWriter`) expects.
struct CrossTieShortcut: Sendable, Hashable {
    /// Shortcut base name (no `.lnk`).
    var name: String
    /// Windows path of the target executable (may embed arguments).
    var target: String
    /// Windows path of the `.lnk` to create (always ends in `.lnk`).
    var linkPath: String
    var workingDirectory: String?
    var arguments: [String]
}

/// A pre/post-install environment variable. There is no `InstallStep` field for
/// these, so they are surfaced in the run-installer step's `description`.
struct CrossTieEnvironment: Sendable, Hashable {
    var isPreInstall: Bool
    var name: String
    var value: String
}

/// All install-relevant data extracted for one `appid`.
struct CrossTieInstallRecord: Sendable {
    var appID: String

    // `<appprofile>`
    var downloadURLs: [String: String] = [:]      // lang -> url
    var downloadURLs64: [String: String] = [:]    // lang -> url
    var downloadGlob: String?
    var downloadPageURLs: [String: String] = [:]  // lang -> url
    var installerIDs: [String] = []               // referenced app ids
    var installedKeyPattern: String?
    var installedFileGlob: String?

    // `<installprofile>`
    var windowsVersion: String?
    var dllOverrides: [String] = []
    var installerOptions: [String] = []
    var silentOptions: [String] = []
    var installerGlobs: [String] = []
    var localInstallerGlobs: [String] = []
    var selfExtractOption: String?
    var selfExtractSilentOption: String?
    var selfExtractThreshold: String?
    var registries: [CrossTieRegistryEntry] = []
    var fileCopies: [CrossTieFileCopy] = []
    var shortcuts: [CrossTieShortcut] = []
    var environments: [CrossTieEnvironment] = []
    var predependencies: [String] = []
    var postInstallURLs: [String: String] = [:]   // lang -> url
    var requiresReboot = false
    var hasRebootDirective = false
    var embeddedProfileAppIDs: [String] = []      // `<installprofile appid="…">`

    // `<cdprofile>`
    var cdGlobs: [String] = []

    var hasInstallProfile = false

    /// Union two records for the same `appid` (one per `<cxversion>`).
    mutating func merge(_ other: CrossTieInstallRecord) {
        for (key, value) in other.downloadURLs { downloadURLs[key] = value }
        for (key, value) in other.downloadURLs64 { downloadURLs64[key] = value }
        for (key, value) in other.downloadPageURLs { downloadPageURLs[key] = value }
        for (key, value) in other.postInstallURLs { postInstallURLs[key] = value }

        if let value = other.downloadGlob, !value.isEmpty { downloadGlob = value }
        if let value = other.windowsVersion, !value.isEmpty { windowsVersion = value }
        if let value = other.installedKeyPattern, !value.isEmpty { installedKeyPattern = value }
        if let value = other.installedFileGlob, !value.isEmpty { installedFileGlob = value }
        if let value = other.selfExtractOption, !value.isEmpty { selfExtractOption = value }
        if let value = other.selfExtractSilentOption, !value.isEmpty { selfExtractSilentOption = value }
        if let value = other.selfExtractThreshold, !value.isEmpty { selfExtractThreshold = value }

        Self.appendUnique(&installerIDs, other.installerIDs)
        Self.appendUnique(&dllOverrides, other.dllOverrides)
        Self.appendUnique(&installerOptions, other.installerOptions)
        Self.appendUnique(&silentOptions, other.silentOptions)
        Self.appendUnique(&installerGlobs, other.installerGlobs)
        Self.appendUnique(&localInstallerGlobs, other.localInstallerGlobs)
        Self.appendUnique(&cdGlobs, other.cdGlobs)
        Self.appendUnique(&predependencies, other.predependencies)
        Self.appendUnique(&embeddedProfileAppIDs, other.embeddedProfileAppIDs)
        Self.appendUnique(&registries, other.registries)
        Self.appendUnique(&fileCopies, other.fileCopies)
        Self.appendUnique(&shortcuts, other.shortcuts)
        Self.appendUnique(&environments, other.environments)

        requiresReboot = requiresReboot || other.requiresReboot
        hasRebootDirective = hasRebootDirective || other.hasRebootDirective
        hasInstallProfile = hasInstallProfile || other.hasInstallProfile
    }

    private static func appendUnique<T: Equatable>(_ target: inout [T], _ values: [T]) {
        for value in values where !target.contains(value) { target.append(value) }
    }
}

/// Read-only index of install records for every `appid` in a catalog.
struct CrossTieInstallIndex: Sendable {
    let records: [String: CrossTieInstallRecord]

    func record(for appID: String) -> CrossTieInstallRecord? { records[appID] }
}

// MARK: - Parser

/// Streaming extractor for CrossTie install recipes.
///
/// Streams the catalog once with Foundation's SAX `XMLParser` and keeps only the
/// install-relevant fields, so memory is proportional to the number of unique
/// apps (not the tens of megabytes of XML).
enum CrossTieInstallParser {
    static func parse(fileURL: URL) throws -> CrossTieInstallIndex {
        guard let stream = InputStream(url: fileURL) else {
            throw CrossTieParserError.unreadable(fileURL)
        }
        let delegate = CrossTieInstallSAXDelegate()
        let parser = XMLParser(stream: stream)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "unknown XML error"
            throw CrossTieParserError.malformed(detail)
        }
        return CrossTieInstallIndex(records: delegate.finalizedRecords())
    }
}

// MARK: - Record → steps

extension CrossTieInstallRecord {
    /// Ordered steps for this record. The order mirrors what an install needs:
    /// download → set Windows version → pre-install registry → run installer →
    /// post-install registry → copy files → create shortcuts.
    ///
    /// Elements that have no `InstallStep` field (dependencies, environment,
    /// self-extract flags, CD globs, post-install URLs, embedded profiles) are
    /// recorded in the run-installer step's `description`, or in the first step
    /// when there is no run-installer step.
    func installSteps() -> [InstallStep] {
        var steps: [InstallStep] = []

        // 1. Download(s).
        if let url = preferred(downloadURLs) {
            var notes: [String] = []
            if let alt = preferred(downloadURLs64), alt != url {
                notes.append("64-bit alternative: \(alt)")
            }
            steps.append(InstallStep(
                kind: .download,
                url: url,
                fileName: downloadFileName(fallbackURL: url),
                description: notes.isEmpty ? "download installer" : notes.joined(separator: "; ")
            ))
        } else if let url = preferred(downloadURLs64) {
            steps.append(InstallStep(
                kind: .download,
                url: url,
                fileName: downloadFileName(fallbackURL: url),
                description: "download 64-bit installer"
            ))
        }

        // 2. Windows version for the installer.
        if let version = windowsVersion, !version.isEmpty {
            steps.append(InstallStep(
                kind: .setWindowsVersion,
                windowsVersion: version,
                description: "installer Windows version"
            ))
        }

        // 3. Pre-install registry.
        for entry in registries where entry.isPreInstall {
            steps.append(registryStep(entry, label: "pre-install registry"))
        }

        // 4. Run the installer itself.
        let notes = informationalNotes()
        if let command = installerCommand() {
            steps.append(InstallStep(
                kind: .runInstaller,
                command: command,
                arguments: Self.splitArguments(installerOptions),
                silentArguments: Self.splitArguments(silentOptions),
                description: notes.isEmpty ? "run installer" : notes.joined(separator: "; ")
            ))
        }

        // 5. Post-install registry.
        for entry in registries where !entry.isPreInstall {
            steps.append(registryStep(entry, label: "post-install registry"))
        }

        // 6. Copy files (recipes copy post-install, e.g. StarCraft's CD data).
        for copy in fileCopies {
            steps.append(InstallStep(
                kind: .copyFiles,
                source: copy.source,
                destination: copy.destination,
                description: "copy files"
            ))
        }

        // 7. Shortcuts.
        for shortcut in shortcuts {
            steps.append(InstallStep(
                kind: .createShortcut,
                fileName: shortcut.name,
                arguments: shortcut.arguments,
                workingDirectory: shortcut.workingDirectory,
                source: shortcut.linkPath,
                destination: shortcut.target,
                description: "create shortcut"
            ))
        }

        // Notes with nowhere else to go: attach to the first step so nothing is
        // silently lost when a recipe has no run-installer step.
        if !notes.isEmpty, !steps.contains(where: { $0.kind == .runInstaller }), !steps.isEmpty {
            let existing = steps[0].description
            steps[0].description = [existing, notes.joined(separator: "; ")].compactMap { $0 }.joined(separator: "; ")
        }

        return steps
    }

    private func registryStep(_ entry: CrossTieRegistryEntry, label: String) -> InstallStep {
        InstallStep(
            kind: .registry,
            registryKey: entry.key,
            registryName: entry.name,
            registryData: entry.data,
            description: label
        )
    }

    /// The best guess at the installer executable's file name.
    ///
    /// `<installerglob>` (an installer unpacked from a download) is preferred,
    /// then the downloaded file (`<downloadglob>`), a `<localinstallerglob>`
    /// (bundle/CD installer), and finally the download URL's basename.
    ///
    /// `<cdglob>` is deliberately *not* a candidate: it identifies the CD for
    /// detection (`<cdprofile>`), not the installer (e.g. `autorun.inf`, `SC.ICO`).
    private func installerCommand() -> String? {
        for candidate in installerGlobs { if let name = Self.basename(candidate), !name.isEmpty { return name } }
        if let glob = downloadGlob, !glob.isEmpty, let name = Self.basename(glob), !name.isEmpty { return name }
        for candidate in localInstallerGlobs { if let name = Self.basename(candidate), !name.isEmpty { return name } }
        if let url = preferred(downloadURLs) { return Self.fileName(fromURL: url) }
        if let url = preferred(downloadURLs64) { return Self.fileName(fromURL: url) }
        return nil
    }

    private func downloadFileName(fallbackURL: String) -> String? {
        if let glob = downloadGlob, !glob.isEmpty { return Self.basename(glob) ?? glob }
        return Self.fileName(fromURL: fallbackURL)
    }

    /// Free-form notes for recipe metadata with no first-class `InstallStep`
    /// representation.
    private func informationalNotes() -> [String] {
        var notes: [String] = []
        if !predependencies.isEmpty { notes.append("requires \(predependencies.joined(separator: ", "))") }
        for environment in environments {
            notes.append("\(environment.isPreInstall ? "pre" : "post") env \(environment.name)=\(environment.value)")
        }
        if let option = selfExtractOption { notes.append("self-extract option \(option)") }
        if let threshold = selfExtractThreshold { notes.append("self-extract threshold \(threshold)") }
        if !cdGlobs.isEmpty { notes.append("CD \(cdGlobs.joined(separator: ", "))") }
        if let url = preferred(postInstallURLs) { notes.append("post-install \(url)") }
        if !embeddedProfileAppIDs.isEmpty {
            notes.append("embedded profile for \(embeddedProfileAppIDs.joined(separator: ", "))")
        }
        return notes
    }

    // MARK: Value helpers

    /// Prefer the untagged string, then `en`, then any non-empty value.
    private func preferred(_ values: [String: String]) -> String? {
        if let value = values[""], !value.isEmpty { return value }
        if let value = values["en"], !value.isEmpty { return value }
        return values.sorted { $0.key < $1.key }.first { !$0.value.isEmpty }?.value
    }

    private static func splitArguments(_ raw: [String]) -> [String] {
        raw.flatMap { value in
            value.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        }
    }

    /// Last path component, accepting both `/` and `\`.
    static func basename(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        if let range = normalized.range(of: "/", options: .backwards) {
            let base = String(normalized[range.upperBound...])
            return base.isEmpty ? nil : base
        }
        return normalized
    }

    /// Derive a file name from a URL the same way the installer does.
    static func fileName(fromURL urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var base = url.lastPathComponent
        if base.isEmpty { base = (url.path as NSString).lastPathComponent }
        base = base.removingPercentEncoding ?? base
        return base.isEmpty ? nil : base
    }
}

// MARK: - SAX delegate

private final class CrossTieInstallSAXDelegate: NSObject, XMLParserDelegate {
    private struct PendingRegistry {
        var isPre: Bool
        var key = ""
        var name = ""
        var data = ""
    }

    private struct PendingFileCopy {
        var glob = ""
        var dst = ""
    }

    private struct PendingShortcut {
        var shortcut = ""
        var target = ""
        var workdir: String?
    }

    private struct PendingEnvironment {
        var isPre: Bool
        var name = ""
        var value = ""
    }

    private struct PendingCDGlob {
        var glob = ""
        var pattern = ""
    }

    private var merged: [String: CrossTieInstallRecord] = [:]
    private var current: CrossTieInstallRecord?

    private var stack: [String] = []
    private var text = ""
    private var attributes: [String: String] = [:]

    private var insideAppProfile = false
    private var insideInstallProfile = false

    private var pendingRegistry: PendingRegistry?
    private var pendingFileCopy: PendingFileCopy?
    private var pendingShortcut: PendingShortcut?
    private var pendingEnvironment: PendingEnvironment?
    private var pendingCDGlob: PendingCDGlob?

    func finalizedRecords() -> [String: CrossTieInstallRecord] { merged }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        text.removeAll(keepingCapacity: true)
        attributes = attributeDict
        stack.append(elementName)

        switch elementName {
        case "app":
            if let appid = attributeDict["appid"], !appid.isEmpty {
                current = CrossTieInstallRecord(appID: appid)
            } else {
                current = nil
            }
        case "appprofile":
            insideAppProfile = true
        case "installprofile":
            insideInstallProfile = true
            current?.hasInstallProfile = true
            if let profileAppID = attributeDict["appid"], !profileAppID.isEmpty {
                current?.embeddedProfileAppIDs.append(profileAppID)
            }
        case "preinstallregistry":
            pendingRegistry = PendingRegistry(isPre: true)
        case "postinstallregistry":
            pendingRegistry = PendingRegistry(isPre: false)
        case "filestocopy":
            pendingFileCopy = PendingFileCopy()
        case "lnkfile":
            pendingShortcut = PendingShortcut()
        case "preinstallenvironment":
            pendingEnvironment = PendingEnvironment(isPre: true)
        case "installerenvironment":
            pendingEnvironment = PendingEnvironment(isPre: false)
        case "cdglob":
            pendingCDGlob = PendingCDGlob()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let decoded = String(data: CDATABlock, encoding: .utf8) { text += decoded }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.count >= 2 ? stack[stack.count - 2] : nil
        let grandparent = stack.count >= 3 ? stack[stack.count - 3] : nil
        let lang = attributes["lang"] ?? ""

        stack.removeLast()
        text.removeAll(keepingCapacity: true)
        attributes.removeAll(keepingCapacity: true)

        switch elementName {
        case "app":
            if let record = current { store(record) }
            current = nil
        case "appprofile":
            insideAppProfile = false
        case "installprofile":
            insideInstallProfile = false
        default:
            guard current != nil else { return }
            handleLeaf(elementName, value: value, parent: parent, grandparent: grandparent, lang: lang)
        }
    }

    private func handleLeaf(
        _ elementName: String,
        value: String,
        parent: String?,
        grandparent: String?,
        lang: String
    ) {
        switch elementName {
        // `<appprofile>`
        case "downloadurl":
            if insideAppProfile, !value.isEmpty { current?.downloadURLs[lang] = value }
        case "downloadurl64":
            if insideAppProfile, !value.isEmpty { current?.downloadURLs64[lang] = value }
        case "downloadglob":
            if insideAppProfile, !value.isEmpty { current?.downloadGlob = value }
        case "downloadpageurl":
            if insideAppProfile, !value.isEmpty { current?.downloadPageURLs[lang] = value }
        case "installerid":
            if insideAppProfile, !value.isEmpty, current?.installerIDs.contains(value) != true {
                current?.installerIDs.append(value)
            }
        case "installedkeypattern":
            if insideAppProfile, !value.isEmpty { current?.installedKeyPattern = value }
        case "installedfileglob":
            if insideAppProfile, !value.isEmpty { current?.installedFileGlob = value }

        // `<installprofile>` scalars / lists
        case "installerwinver":
            if insideInstallProfile, !value.isEmpty { current?.windowsVersion = value }
        case "installerdlloverrides":
            if insideInstallProfile, !value.isEmpty {
                for override in value.split(separator: ";") {
                    let token = override.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !token.isEmpty, current?.dllOverrides.contains(token) != true {
                        current?.dllOverrides.append(token)
                    }
                }
            }
        case "installeroption":
            if insideInstallProfile, !value.isEmpty { current?.installerOptions.append(value) }
        case "installersilentoption":
            if insideInstallProfile, !value.isEmpty { current?.silentOptions.append(value) }
        case "selfextractoption":
            if insideInstallProfile, !value.isEmpty { current?.selfExtractOption = value }
        case "selfextractsilentoption":
            if insideInstallProfile, !value.isEmpty { current?.selfExtractSilentOption = value }
        case "selfextractthreshold":
            if insideInstallProfile, !value.isEmpty { current?.selfExtractThreshold = value }
        case "installerglob":
            if insideInstallProfile, !value.isEmpty, current?.installerGlobs.contains(value) != true {
                current?.installerGlobs.append(value)
            }
        case "localinstallerglob":
            if insideInstallProfile, !value.isEmpty, current?.localInstallerGlobs.contains(value) != true {
                current?.localInstallerGlobs.append(value)
            }
        case "postinstallurl":
            if insideInstallProfile, !value.isEmpty { current?.postInstallURLs[lang] = value }
        case "postinstallreboot":
            if insideInstallProfile {
                current?.hasRebootDirective = true
                if value.lowercased() == "true" { current?.requiresReboot = true }
            }
        case "predependency":
            if insideInstallProfile, !value.isEmpty, current?.predependencies.contains(value) != true {
                current?.predependencies.append(value)
            }

        // `<preinstallregistry>` / `<postinstallregistry>`
        case "key":
            if parent == "preinstallregistry" || parent == "postinstallregistry" { pendingRegistry?.key = value }
        case "name":
            if parent == "installerenvironment" || parent == "preinstallenvironment" {
                pendingEnvironment?.name = value
            } else if parent == "value", grandparent == "preinstallregistry" || grandparent == "postinstallregistry" {
                pendingRegistry?.name = value
            }
        case "data":
            if parent == "value", grandparent == "preinstallregistry" || grandparent == "postinstallregistry" {
                pendingRegistry?.data = value
            }
        case "value":
            if parent == "installerenvironment" || parent == "preinstallenvironment" {
                pendingEnvironment?.value = value
            }
        case "preinstallregistry", "postinstallregistry":
            if let registry = pendingRegistry, !registry.key.isEmpty {
                current?.registries.append(CrossTieRegistryEntry(
                    isPreInstall: elementName == "preinstallregistry",
                    key: registry.key,
                    name: registry.name,
                    data: registry.data
                ))
            }
            pendingRegistry = nil

        // `<filestocopy>` / `<cdglob>`
        case "glob":
            if parent == "filestocopy" { pendingFileCopy?.glob = value }
            if parent == "cdglob" { pendingCDGlob?.glob = value }
        case "dst":
            if parent == "filestocopy" { pendingFileCopy?.dst = value }
        case "pattern":
            if parent == "cdglob" { pendingCDGlob?.pattern = value }
        case "filestocopy":
            if let copy = pendingFileCopy, !(copy.glob.isEmpty && copy.dst.isEmpty) {
                current?.fileCopies.append(CrossTieFileCopy(source: copy.glob, destination: copy.dst))
            }
            pendingFileCopy = nil
        case "cdglob":
            if let cd = pendingCDGlob, !cd.glob.isEmpty, current?.cdGlobs.contains(cd.glob) != true {
                current?.cdGlobs.append(cd.glob)
            }
            pendingCDGlob = nil

        // `<lnkfile>`
        case "shortcut":
            if parent == "lnkfile" { pendingShortcut?.shortcut = value }
        case "target":
            if parent == "lnkfile" { pendingShortcut?.target = value }
        case "workdir":
            if parent == "lnkfile" { pendingShortcut?.workdir = value }
        case "lnkfile":
            if let shortcut = pendingShortcut,
               let resolved = Self.makeShortcut(shortcut) {
                current?.shortcuts.append(resolved)
            }
            pendingShortcut = nil

        // `<installerenvironment>` / `<preinstallenvironment>`
        case "preinstallenvironment", "installerenvironment":
            if let environment = pendingEnvironment, !environment.name.isEmpty {
                current?.environments.append(CrossTieEnvironment(
                    isPreInstall: elementName == "preinstallenvironment",
                    name: environment.name,
                    value: environment.value
                ))
            }
            pendingEnvironment = nil

        default:
            break
        }
    }

    private func store(_ record: CrossTieInstallRecord) {
        if var existing = merged[record.appID] {
            existing.merge(record)
            merged[record.appID] = existing
        } else {
            merged[record.appID] = record
        }
    }

    // MARK: Shortcut resolution

    /// Turn a raw `<lnkfile>` into a `CrossTieShortcut`, splitting any arguments
    /// embedded in `<target>` (e.g. `"…\BF2.exe" +fullscreen 0`).
    private static func makeShortcut(_ raw: PendingShortcut) -> CrossTieShortcut? {
        let link = raw.shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = raw.target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(link.isEmpty && target.isEmpty) else { return nil }

        let parsed = splitTarget(target)
        var name = CrossTieInstallRecord.basename(link) ?? ""
        if name.lowercased().hasSuffix(".lnk") { name = String(name.dropLast(4)) }
        var linkPath = link
        if !link.isEmpty, !linkPath.lowercased().hasSuffix(".lnk") { linkPath += ".lnk" }
        if name.isEmpty { name = CrossTieInstallRecord.basename(parsed.target) ?? "" }

        var workingDirectory: String?
        if let workdir = raw.workdir {
            let trimmed = workdir.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { workingDirectory = unquote(trimmed) }
        }

        return CrossTieShortcut(
            name: name,
            target: parsed.target,
            linkPath: linkPath,
            workingDirectory: workingDirectory,
            arguments: parsed.arguments
        )
    }

    /// Split a quoted executable path from trailing arguments.
    static func splitTarget(_ raw: String) -> (target: String, arguments: [String]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\"") else { return (unquote(trimmed), []) }
        let afterOpening = trimmed.index(after: trimmed.startIndex)
        if let closing = trimmed[afterOpening...].firstIndex(of: "\"") {
            let target = String(trimmed[afterOpening..<closing])
            let rest = String(trimmed[trimmed.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
            return (target, rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init))
        }
        return (unquote(trimmed), [])
    }

    static func unquote(_ value: String) -> String {
        var result = value
        if result.count >= 2, result.hasPrefix("\""), result.hasSuffix("\"") {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }
}
