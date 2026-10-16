import Foundation

/// Errors thrown by ``CrossTieParser``.
public enum CrossTieParserError: Error, CustomStringConvertible {
    /// The file could not be opened for reading.
    case unreadable(URL)
    /// The XML was malformed / could not be parsed.
    case malformed(String)

    public var description: String {
        switch self {
        case .unreadable(let url):
            return "Unable to read CrossTie catalog at \(url.path)"
        case .malformed(let detail):
            return "Malformed CrossTie catalog: \(detail)"
        }
    }
}

/// Streaming parser for the CrossTie (`c4p`) XML catalog.
///
/// The real `crossover.tie` is ~23 MB with thousands of `<app>` records, so this
/// uses Foundation's SAX-style `XMLParser` (no DOM) and folds each record into a
/// per-`appid` accumulator as it goes. Memory use is therefore proportional to
/// the number of *unique* apps, not the size of the XML.
///
/// The same `appid` appears many times (once per `<cxversion>`); those records
/// are merged, keeping the richest/newest record for scalar fields and unioning
/// the collection-valued ones (dependencies, medals, associations, …).
public enum CrossTieParser {
    /// Parse a CrossTie XML file into an in-memory ``CrossTieIndex``.
    public static func parse(fileURL: URL) throws -> CrossTieIndex {
        guard let stream = InputStream(url: fileURL) else {
            throw CrossTieParserError.unreadable(fileURL)
        }
        let delegate = CrossTieSAXDelegate()
        let parser = XMLParser(stream: stream)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "unknown XML error"
            throw CrossTieParserError.malformed(detail)
        }
        return CrossTieIndex(apps: delegate.finalizedApps())
    }
}

// MARK: - Version comparison

/// Dotted-numeric version helper (e.g. `9.0`, `12.1.2`).
enum CrossTieVersion {
    static func components(_ string: String) -> [Int] {
        string
            .split(whereSeparator: { !$0.isNumber })
            .map { Int($0) ?? 0 }
    }

    /// Lexicographic comparison of dotted version components (missing == 0).
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        compare(components(lhs), components(rhs))
    }

    static func compare(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func isLess(_ lhs: String, _ rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }
}

// MARK: - Per-record model

private struct CrossTieMedal {
    var rating: Int
    var platform: String
    var version: String
    var label: String
}

/// One `<app>` element's worth of data.
private struct CrossTieAppRecord {
    let id: String
    var names: [String: String] = [:]          // lang ("" == no lang) -> value
    var descriptions: [String: String] = [:]
    var installNotes: [String: String] = [:]
    var category: String?
    var bottleTemplates: [String] = []
    var dependencies: [String] = []
    var installerVersion: String?
    var installerIDs: [String] = []
    var defaultAssociations: [String] = []
    var hasInstallerContent = false
    var medals: [CrossTieMedal] = []
    var versions: [String] = []

    var hasInstallerRecord: Bool { hasInstallerContent || !installerIDs.isEmpty }

    var maxVersion: String? {
        versions.max { CrossTieVersion.isLess($0, $1) }
    }

    var maxVersionComponents: [Int] {
        maxVersion.map(CrossTieVersion.components) ?? []
    }

    /// Rough measure of how much useful data this record carries, used to pick
    /// the "richest" record when an appid appears multiple times.
    var fieldCount: Int {
        var count = 0
        if !names.isEmpty { count += 1 }
        if descriptions.values.contains(where: { !$0.isEmpty }) { count += 1 }
        if category?.isEmpty == false { count += 1 }
        if !bottleTemplates.isEmpty { count += 1 }
        if !dependencies.isEmpty { count += 1 }
        if installerVersion?.isEmpty == false { count += 1 }
        if installNotes.values.contains(where: { !$0.isEmpty }) { count += 1 }
        if !defaultAssociations.isEmpty { count += 1 }
        if !medals.isEmpty { count += 1 }
        if hasInstallerRecord { count += 1 }
        return count
    }
}

/// Accumulator merging every `<app>` record that shares one `appid`.
private struct CrossTieMergedRecord {
    let id: String
    var best: CrossTieAppRecord
    var names: [String: String]
    var descriptions: [String: String]
    var installNotes: [String: String]
    var dependencies: [String]
    var defaultAssociations: [String]
    var medals: [CrossTieMedal]
    var versions: [String]
    var hasInstaller: Bool
    var platformSet: Set<String>
    var fallbackCategory: String?
    var fallbackInstallerVersion: String?

    init(record: CrossTieAppRecord) {
        id = record.id
        best = record
        names = record.names
        descriptions = record.descriptions
        installNotes = record.installNotes
        dependencies = record.dependencies
        defaultAssociations = record.defaultAssociations
        medals = record.medals
        versions = record.versions
        hasInstaller = record.hasInstallerRecord
        platformSet = Set(record.medals.map(\.platform).filter { !$0.isEmpty })
        fallbackCategory = record.category
        fallbackInstallerVersion = record.installerVersion
    }

    mutating func merge(_ record: CrossTieAppRecord) {
        hasInstaller = hasInstaller || record.hasInstallerRecord
        medals.append(contentsOf: record.medals)
        versions.append(contentsOf: record.versions)
        for platform in record.medals.map(\.platform) where !platform.isEmpty {
            platformSet.insert(platform)
        }
        for (key, value) in record.names where names[key] == nil { names[key] = value }
        for (key, value) in record.descriptions where descriptions[key] == nil { descriptions[key] = value }
        for (key, value) in record.installNotes where installNotes[key] == nil { installNotes[key] = value }
        for dependency in record.dependencies where !dependencies.contains(dependency) {
            dependencies.append(dependency)
        }
        for association in record.defaultAssociations where !defaultAssociations.contains(association) {
            defaultAssociations.append(association)
        }
        if fallbackCategory == nil { fallbackCategory = record.category }
        if fallbackInstallerVersion == nil { fallbackInstallerVersion = record.installerVersion }
        if Self.isRicher(record, than: best) { best = record }
    }

    /// "Richest/newest": a record with an installer beats one without, then the
    /// higher `<cxversion>`, then the one carrying more populated fields.
    static func isRicher(_ lhs: CrossTieAppRecord, than rhs: CrossTieAppRecord) -> Bool {
        if lhs.hasInstallerRecord != rhs.hasInstallerRecord { return lhs.hasInstallerRecord }
        let versionOrder = CrossTieVersion.compare(lhs.maxVersionComponents, rhs.maxVersionComponents)
        if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
        if lhs.fieldCount != rhs.fieldCount { return lhs.fieldCount > rhs.fieldCount }
        return false
    }

    func finalized() -> RecipeApp {
        let medal = Self.bestMedal(medals)
        let name = Self.preferredLocalized(names) ?? best.id
        let medalPlatform = medal.flatMap { $0.platform.isEmpty ? nil : $0.platform }
        return RecipeApp(
            id: id,
            name: name,
            localizedNames: names.filter { !$0.key.isEmpty && !$0.value.isEmpty },
            summary: Self.preferredLocalized(descriptions),
            category: best.category ?? fallbackCategory,
            rating: medal?.rating,
            medal: medal?.label,
            medalPlatform: medalPlatform,
            bottleTemplate: best.bottleTemplates.first,
            dependencies: dependencies,
            installerVersion: best.installerVersion ?? fallbackInstallerVersion,
            hasInstaller: hasInstaller,
            platforms: platformSet.sorted(),
            version: versions.max { CrossTieVersion.isLess($0, $1) },
            installNotes: Self.preferredLocalized(installNotes),
            defaultAssociations: defaultAssociations
        )
    }

    /// Prefer the un-tagged (usually English) string, then `en`, then anything.
    static func preferredLocalized(_ values: [String: String]) -> String? {
        if let untagged = values[""], !untagged.isEmpty { return untagged }
        if let english = values["en"], !english.isEmpty { return english }
        return values.sorted { $0.key < $1.key }.first { !$0.value.isEmpty }?.value
    }

    /// Highest rating wins; ties prefer `Mac`, then a verified ("non-`un`")
    /// medal, then the newest recorded version.
    static func bestMedal(_ medals: [CrossTieMedal]) -> CrossTieMedal? {
        medals.reduce(into: CrossTieMedal?.none) { best, candidate in
            if let current = best {
                if medal(candidate, beats: current) { best = candidate }
            } else {
                best = candidate
            }
        }
    }

    static func medal(_ lhs: CrossTieMedal, beats rhs: CrossTieMedal) -> Bool {
        if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
        let lhsMac = lhs.platform == "Mac"
        let rhsMac = rhs.platform == "Mac"
        if lhsMac != rhsMac { return lhsMac }
        let lhsVerified = !lhs.label.lowercased().hasPrefix("un")
        let rhsVerified = !rhs.label.lowercased().hasPrefix("un")
        if lhsVerified != rhsVerified { return lhsVerified }
        let versionOrder = CrossTieVersion.compare(lhs.version, rhs.version)
        if versionOrder != .orderedSame { return versionOrder == .orderedDescending }
        return lhs.label < rhs.label
    }
}

// MARK: - SAX delegate

private final class CrossTieSAXDelegate: NSObject, XMLParserDelegate {
    private var merged: [String: CrossTieMergedRecord] = [:]
    private var order: [String] = []

    private var current: CrossTieAppRecord?
    private var insideAppProfile = false
    private var insideInstallProfile = false
    private var text = ""

    private var pendingLang: String?
    private var pendingMedalRating: Int?
    private var pendingMedalPlatform: String?
    private var pendingMedalVersion: String?

    func finalizedApps() -> [RecipeApp] {
        order.compactMap { merged[$0]?.finalized() }
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        text.removeAll(keepingCapacity: true)

        switch elementName {
        case "app":
            if let appid = attributeDict["appid"], !appid.isEmpty {
                current = CrossTieAppRecord(id: appid)
            } else {
                current = nil
            }
            return
        case "appprofile":
            insideAppProfile = true
            return
        case "installprofile":
            insideInstallProfile = true
            return
        default:
            break
        }

        guard current != nil else { return }

        // Any child element inside an install profile means there is real
        // installer content (self-closing `<installprofile/>` sets nothing).
        if insideInstallProfile {
            current?.hasInstallerContent = true
        }

        switch elementName {
        case "name":
            if !insideInstallProfile { pendingLang = attributeDict["lang"] }
        case "description":
            if insideAppProfile { pendingLang = attributeDict["lang"] }
        case "installnotes":
            if insideInstallProfile || insideAppProfile { pendingLang = attributeDict["lang"] }
        case "medal":
            if insideAppProfile {
                pendingMedalRating = attributeDict["rating"].flatMap(Int.init)
                pendingMedalPlatform = attributeDict["platform"]
                pendingMedalVersion = attributeDict["version"]
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let decoded = String(data: CDATABlock, encoding: .utf8) {
            text += decoded
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text.removeAll(keepingCapacity: true)

        switch elementName {
        case "app":
            if let record = current { store(record) }
            current = nil
        case "appprofile":
            insideAppProfile = false
        case "installprofile":
            insideInstallProfile = false
        case "cxversion":
            if !insideInstallProfile, !value.isEmpty { current?.versions.append(value) }
        case "name":
            if !insideInstallProfile, !value.isEmpty { current?.names[pendingLang ?? ""] = value }
        case "description":
            if insideAppProfile, !value.isEmpty { current?.descriptions[pendingLang ?? ""] = value }
        case "installnotes":
            if (insideInstallProfile || insideAppProfile), !value.isEmpty {
                current?.installNotes[pendingLang ?? ""] = value
            }
        case "installerwinver":
            if insideInstallProfile, !value.isEmpty { current?.installerVersion = value }
        case "predependency":
            if insideInstallProfile, !value.isEmpty, current?.dependencies.contains(value) != true {
                current?.dependencies.append(value)
            }
        case "defaulteassoc":
            if insideInstallProfile, !value.isEmpty, current?.defaultAssociations.contains(value) != true {
                current?.defaultAssociations.append(value)
            }
        case "category":
            if insideAppProfile, !value.isEmpty { current?.category = value }
        case "bottletemplate":
            if insideAppProfile, !value.isEmpty, current?.bottleTemplates.contains(value) != true {
                current?.bottleTemplates.append(value)
            }
        case "installerid":
            if insideAppProfile, !value.isEmpty { current?.installerIDs.append(value) }
        case "medal":
            if insideAppProfile, let rating = pendingMedalRating, !value.isEmpty {
                current?.medals.append(
                    CrossTieMedal(
                        rating: rating,
                        platform: pendingMedalPlatform ?? "",
                        version: pendingMedalVersion ?? "",
                        label: value
                    )
                )
            }
        default:
            break
        }
    }

    private func store(_ record: CrossTieAppRecord) {
        if var existing = merged[record.id] {
            existing.merge(record)
            merged[record.id] = existing
        } else {
            merged[record.id] = CrossTieMergedRecord(record: record)
            order.append(record.id)
        }
    }
}
