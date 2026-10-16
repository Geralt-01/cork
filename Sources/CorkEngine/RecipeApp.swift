import Foundation

/// A single application entry from a CrossTie-style recipe catalog.
///
/// This is the provider-neutral model that Cork's UI and installer consume. It is
/// deliberately independent of XML so catalogs can come from any source (a user
/// supplied `crossover.tie`, a Cork-native catalog, a remote index, …).
///
/// NOTE: this type is part of the frozen CorkEngine API surface. New fields may
/// be added (with defaults) but existing fields should not be renamed or removed
/// without updating every consumer.
public struct RecipeApp: Identifiable, Sendable, Hashable, Codable {
    /// Stable identifier, e.g. `com.codeweavers.c4.1`.
    public var id: String
    /// Default (usually English) display name.
    public var name: String
    /// Localized names keyed by language tag (`en`, `de`, `ja`, …).
    public var localizedNames: [String: String]
    /// Short description / marketing blurb.
    public var summary: String?
    /// Category path, e.g. `Productivity/Word Processing`.
    public var category: String?
    /// Medal rating 1…5, if known.
    public var rating: Int?
    /// Medal label, e.g. `gold`, `silver`, `bronze`, `ungold`.
    public var medal: String?
    /// Platform the rating applies to (`Mac`, `Linux`, `Android`).
    public var medalPlatform: String?
    /// CrossOver bottle template this recipe expects, e.g. `win98`, `winxp`.
    public var bottleTemplate: String?
    /// Required recipes (app ids) that must be installed first.
    public var dependencies: [String]
    /// The Windows version the installer wants, if the recipe specifies one.
    public var installerVersion: String?
    /// Whether the recipe describes an automated install (vs. metadata only).
    public var hasInstaller: Bool
    /// Platforms this entry targets.
    public var platforms: [String]
    /// Version string from `<cxversion>`.
    public var version: String?
    /// Human-readable install notes.
    public var installNotes: String?
    /// File extensions the app registers by default, e.g. `.psd`.
    public var defaultAssociations: [String]

    public init(
        id: String,
        name: String,
        localizedNames: [String: String] = [:],
        summary: String? = nil,
        category: String? = nil,
        rating: Int? = nil,
        medal: String? = nil,
        medalPlatform: String? = nil,
        bottleTemplate: String? = nil,
        dependencies: [String] = [],
        installerVersion: String? = nil,
        hasInstaller: Bool = false,
        platforms: [String] = [],
        version: String? = nil,
        installNotes: String? = nil,
        defaultAssociations: [String] = []
    ) {
        self.id = id
        self.name = name
        self.localizedNames = localizedNames
        self.summary = summary
        self.category = category
        self.rating = rating
        self.medal = medal
        self.medalPlatform = medalPlatform
        self.bottleTemplate = bottleTemplate
        self.dependencies = dependencies
        self.installerVersion = installerVersion
        self.hasInstaller = hasInstaller
        self.platforms = platforms
        self.version = version
        self.installNotes = installNotes
        self.defaultAssociations = defaultAssociations
    }
}
