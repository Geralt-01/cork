import Foundation
import SwiftUI
import AppKit
import CorkKit
import CorkEngine

/// A single user-facing alert. The root view presents whatever is set here.
struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// The single source of truth for the GUI. Owns the CorkKit managers, the
/// loaded catalog, and everything the views need to render.
@MainActor
final class AppModel: ObservableObject {

    enum Section: String, CaseIterable, Identifiable {
        case bottles
        case applications
        case files
        case dependencies
        case diagnostics

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bottles: return "Bottles"
            case .applications: return "Applications"
            case .files: return "Bottle Files"
            case .dependencies: return "Dependencies"
            case .diagnostics: return "Diagnostics"
            }
        }

        var systemImage: String {
            switch self {
            case .bottles: return "shippingbox"
            case .applications: return "square.grid.2x2"
            case .files: return "folder"
            case .dependencies: return "puzzlepiece.extension"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    // MARK: Stored dependencies

    let paths: CorkPaths
    let runtime: RuntimeManager?
    let bottleManager: BottleManager?

    /// Populated when the managers could not be constructed at launch (e.g. the
    /// bundled runtime manifest is missing). The app still runs and shows this.
    let startupError: String?

    // MARK: Navigation

    @Published var section: Section? = .bottles

    // MARK: Bottles

    @Published var bottles: [Bottle] = []
    @Published var bottleIssues: [BottleListing.Issue] = []
    @Published var selectedBottleName: String?

    /// Serializes setting writes from the detail pane and tracks the newest
    /// edit so stale results are not reflected back into the UI.
    private var pendingSettingUpdate: Task<Void, Never>?
    private var settingRevision = 0

    // MARK: Create sheet

    @Published var showCreateSheet = false
    @Published var isCreating = false
    @Published var createLog: [String] = []
    @Published var createError: String?
    @Published var createdBottleName: String?

    // MARK: Logs sheet

    @Published var logsBottleName: String?
    @Published var logsText: String = ""

    // MARK: Catalog

    @Published var catalog: CrossTieCatalog?
    @Published var catalogURL: URL?
    @Published var catalogApps: [RecipeApp] = []
    @Published var catalogCategories: [String] = []
    @Published var catalogSearchText = ""
    @Published var selectedCategory: String?
    @Published var selectedAppID: String?
    @Published var isCatalogLoading = false

    // MARK: Install wizard

    @Published var showInstallSheet = false
    @Published var installAppID = ""
    @Published var installAppName = ""
    /// Existing bottle the recipe installs into.
    @Published var installExistingBottle: String?
    /// When true, a brand-new bottle is created inline before installing.
    @Published var installCreateNewBottle = false
    @Published var installNewBottleName = ""
    @Published var installLog: [String] = []
    @Published var isInstalling = false
    /// `.running` while unanswered; otherwise the terminal outcome.
    @Published var installOutcome: InstallOutcome = .running

    enum InstallOutcome: Equatable {
        case running
        case succeeded
        case failed
        case noRecipe
    }

    // MARK: Bottle file browser

    @Published var filesBottleName: String?
    /// Path components beneath `drive_c` describing the directory being listed.
    @Published var browserComponents: [String] = []
    @Published var browserEntries: [BrowserEntry] = []
    @Published var browserSelectedURL: URL?

    // MARK: Installed / discovered programs

    @Published var discoveredPrograms: [DiscoveredProgram] = []
    @Published var isDiscoveringPrograms = false
    /// Invalidates in-flight scans when the bottle changes, so a slow scan can
    /// never publish another bottle's results.
    private var programScanRevision = 0

    // MARK: App bundling

    @Published var showBundleSheet = false
    @Published var bundleBottleName = ""
    @Published var bundleExecutableURL: URL?
    @Published var bundleName = ""
    @Published var bundleIconPath: URL?
    @Published var bundleOutputDirectory: URL = BottleFiles.defaultApplicationsDirectory
    @Published var bundleArguments = ""
    @Published var isBundling = false
    @Published var bundledAppURL: URL?
    @Published var bundleError: String?

    // MARK: Dependencies

    /// Every component Cork can install, sorted by id.
    @Published var dependencyComponents: [DependencyComponent] = []
    /// Component ids whose recipe can only be completed manually.
    @Published var dependencyManualIDs: Set<String> = []
    @Published var dependencySearchText = ""
    @Published var selectedDependencyCategory: String?
    @Published var selectedDependencyID: String?

    /// Install sheet state for a dependency component.
    @Published var showDependencyInstallSheet = false
    @Published var dependencyInstallComponentID = ""
    @Published var dependencyInstallComponentName = ""
    @Published var dependencyInstallBottle: String?
    @Published var dependencyInstallLog: [String] = []
    @Published var isInstallingDependency = false
    @Published var dependencyInstallOutcome: InstallOutcome = .running

    // MARK: Diagnostics

    @Published var diagnosticReport: DiagnosticReport?
    @Published var diagnosticBottle: String?
    @Published var isRunningDiagnostics = false
    @Published var selectedDiagnosticCheckID: String?

    // MARK: File associations

    @Published var associations: [AssociationEntry] = []
    @Published var associationsBottleName: String?
    @Published var associationsRegistryLines: [String] = []
    @Published var showAssociationsRegistry = false

    /// Add-association sheet state.
    @Published var showAssociationSheet = false
    @Published var associationFormExtension = ""
    @Published var associationFormExecutable = ""
    @Published var associationFormProgID = ""
    @Published var associationFormFriendlyName = ""

    // MARK: Alerts

    @Published var alert: AppAlert?

    // MARK: Init

    init() {
        let paths = CorkPaths.resolve()
        self.paths = paths
        do {
            let runtime = try RuntimeManager(paths: paths)
            self.runtime = runtime
            self.bottleManager = BottleManager(paths: paths, runtime: runtime)
            self.startupError = nil
        } catch {
            self.runtime = nil
            self.bottleManager = nil
            self.startupError = Self.describe(error)
        }
        refreshBottles()
    }

    // MARK: Derived state

    var isWineReady: Bool { runtime?.isWineReady ?? false }

    var selectedBottle: Bottle? {
        bottles.first { $0.name == selectedBottleName }
    }

    var selectedApp: RecipeApp? {
        catalogApps.first { $0.id == selectedAppID }
    }

    var catalogIsEmpty: Bool { (catalog?.appCount ?? 0) == 0 }

    /// Distinct categories across the dependency catalog, sorted.
    var dependencyCategories: [String] {
        Array(Set(dependencyComponents.map(\.category))).sorted()
    }

    /// The dependency catalog narrowed by the current search text and category.
    var filteredDependencyComponents: [DependencyComponent] {
        let query = dependencySearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return dependencyComponents.filter { component in
            if let category = selectedDependencyCategory,
               component.category.caseInsensitiveCompare(category) != .orderedSame {
                return false
            }
            guard !query.isEmpty else { return true }
            if component.id.lowercased().contains(query) { return true }
            if component.name.lowercased().contains(query) { return true }
            if let summary = component.summary, summary.lowercased().contains(query) { return true }
            return false
        }
    }

    var selectedDependency: DependencyComponent? {
        dependencyComponents.first { $0.id == selectedDependencyID }
    }

    /// True when the selected component's recipe contains a manual step.
    func dependencyRequiresManual(_ id: String) -> Bool {
        dependencyManualIDs.contains(id)
    }

    // MARK: Errors

    static func describe(_ error: Error) -> String {
        if let cork = error as? CorkError {
            var text = cork.errorDescription ?? String(describing: cork)
            if let suggestion = cork.recoverySuggestion {
                text += "\n\n\(suggestion)"
            }
            return text
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    func present(_ error: Error, title: String) {
        alert = AppAlert(title: title, message: Self.describe(error))
    }

    func showAlert(title: String, message: String) {
        alert = AppAlert(title: title, message: message)
    }

    // MARK: Refresh

    func refreshAll() {
        switch section ?? .bottles {
        case .bottles: refreshBottles()
        case .applications: refreshCatalog()
        case .files:
            refreshBottles()
            refreshBrowser()
        case .dependencies:
            refreshBottles()
            loadDependencies()
        case .diagnostics:
            refreshBottles()
            runDiagnostics()
        }
    }

    func refreshBottles() {
        guard let manager = bottleManager else {
            bottles = []
            bottleIssues = []
            selectedBottleName = nil
            return
        }
        let listing = manager.listWithIssues()
        bottles = listing.bottles
        bottleIssues = listing.issues

        if let current = selectedBottleName,
           bottles.contains(where: { $0.name == current }) {
            // Keep the current selection.
        } else {
            selectedBottleName = bottles.first?.name
        }
    }

    // MARK: Settings persistence

    func setBackend(_ bottleName: String, _ backend: GraphicsBackend) {
        applySetting(bottleName, key: .backend, value: backend.rawValue)
    }

    func setWindows(_ bottleName: String, _ version: WindowsVersion) {
        applySetting(bottleName, key: .windows, value: version.rawValue)
    }

    func setToggle(_ bottleName: String, key: BottleSettings.Key, _ on: Bool) {
        applySetting(bottleName, key: key, value: on ? "true" : "false")
    }

    func setText(_ bottleName: String, key: BottleSettings.Key, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        applySetting(bottleName, key: key, value: trimmed.isEmpty ? "off" : trimmed)
    }

    /// Applies a setting optimistically so the UI stays responsive, then
    /// persists in the background and reconciles the result.
    ///
    /// Updates are serialized and reconciled in revision order: rapid toggles
    /// or typing must not let an older `setSetting` overwrite a newer one (and
    /// backend switches must not install/remove DLLs concurrently).
    func applySetting(_ bottleName: String, key: BottleSettings.Key, value: String) {
        if let index = bottles.firstIndex(where: { $0.name == bottleName }) {
            try? bottles[index].metadata.settings.apply(key: key.rawValue, value: value)
        }

        settingRevision += 1
        let revision = settingRevision
        let previous = pendingSettingUpdate
        guard let manager = bottleManager else { return }
        let box = UncheckedSendable(manager)
        pendingSettingUpdate = Task {
            _ = await previous?.value
            do {
                let updated = try await Task.detached {
                    try box.value.setSetting(named: bottleName, key: key.rawValue, value: value)
                }.value
                guard revision == settingRevision else { return }
                if let index = bottles.firstIndex(where: { $0.name == bottleName }) {
                    bottles[index] = updated
                }
            } catch {
                guard revision == settingRevision else { return }
                present(error, title: "Could not update setting")
                refreshBottles()
            }
        }
    }

    // MARK: Bottle lifecycle

    func requestCreateBottle() {
        createLog = []
        createError = nil
        createdBottleName = nil
        isCreating = false
        showCreateSheet = true
    }

    func createBottle(name: String, settings: BottleSettings) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let manager = bottleManager else {
            createError = CorkError.runtimeNotInstalled.errorDescription
            return
        }
        guard (try? Bottle.validateName(trimmed)) != nil else {
            createError = CorkError.invalidBottleName(name: trimmed).errorDescription
            return
        }

        isCreating = true
        createError = nil
        createLog = []
        createdBottleName = nil
        createLog.append("Creating “\(trimmed)”…")

        let box = UncheckedSendable(manager)
        Task {
            do {
                let bottle = try await Task.detached { () -> Bottle in
                    try await box.value.create(
                        named: trimmed,
                        settings: settings,
                        onEvent: { event in
                            let line = Self.describe(event)
                            Task { @MainActor in self.appendCreateLog(line) }
                        }
                    )
                }.value
                appendCreateLog("Finished: \(bottle.name)")
                isCreating = false
                createdBottleName = bottle.name
                refreshBottles()
                selectedBottleName = bottle.name
            } catch {
                isCreating = false
                let message = Self.describe(error)
                createError = message
                appendCreateLog("Failed: \(message)")
            }
        }
    }

    func appendCreateLog(_ line: String) {
        createLog.append(line)
    }

    nonisolated static func describe(_ event: BottleCreateEvent) -> String {
        switch event {
        case .bootstrappingPrefix:
            return "Bootstrapping the Windows prefix…"
        case .applyingWindowsVersion:
            return "Applying the Windows version…"
        case .installingGraphics(let backend):
            return "Installing graphics backend: \(backend.displayName)…"
        case .warning(let message):
            return "Warning: \(message)"
        case .created(let path):
            return "Created: \(path)"
        }
    }

    func requestDelete(_ bottleName: String) {
        guard let manager = bottleManager else {
            present(CorkError.runtimeNotInstalled, title: "Cannot delete bottle")
            return
        }
        let box = UncheckedSendable(manager)
        Task {
            do {
                try await Task.detached {
                    try box.value.delete(named: bottleName)
                }.value
                if selectedBottleName == bottleName {
                    selectedBottleName = nil
                }
                refreshBottles()
            } catch {
                present(error, title: "Could not delete “\(bottleName)”")
            }
        }
    }

    func chooseAndRun(bottleName: String) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows Executable"
        panel.message = "Select an .exe to run in “\(bottleName)”."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let bottle = bottles.first(where: { $0.name == bottleName }),
           FileManager.default.fileExists(atPath: bottle.driveCDirectory.path) {
            panel.directoryURL = bottle.driveCDirectory
        }
        if panel.runModal() == .OK, let url = panel.url {
            run(bottleName: bottleName, executable: url)
        }
    }

    func run(bottleName: String, executable: URL) {
        guard let manager = bottleManager else {
            present(CorkError.runtimeNotInstalled, title: "Cannot run program")
            return
        }
        let box = UncheckedSendable(manager)
        Task {
            do {
                let status = try await Task.detached {
                    try box.value.run(named: bottleName, executable: executable)
                }.value
                alert = AppAlert(
                    title: "Run finished",
                    message: "\(executable.lastPathComponent) exited with status \(status)."
                )
            } catch {
                present(error, title: "Could not run \(executable.lastPathComponent)")
            }
        }
    }

    func kill(bottleName: String) {
        guard let manager = bottleManager else {
            present(CorkError.runtimeNotInstalled, title: "Cannot stop processes")
            return
        }
        let box = UncheckedSendable(manager)
        Task {
            do {
                let result = try await Task.detached {
                    try box.value.kill(named: bottleName)
                }.value
                let detail = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                alert = AppAlert(
                    title: "Processes stopped",
                    message: detail.isEmpty
                        ? "wineserver exited with status \(result.status)."
                        : detail
                )
            } catch {
                present(error, title: "Could not stop processes in “\(bottleName)”")
            }
        }
    }

    func loadLogs(bottleName: String) {
        guard let bottle = bottles.first(where: { $0.name == bottleName }) else { return }
        guard let url = bottle.latestLogFile() else {
            showAlert(
                title: "No logs yet",
                message: "No log files were found for “\(bottleName)”."
            )
            return
        }
        if let data = try? Data(contentsOf: url) {
            logsText = String(decoding: data, as: UTF8.self)
            logsBottleName = bottleName
        } else {
            showAlert(
                title: "Could not read log",
                message: "The most recent log (\(url.lastPathComponent)) could not be read."
            )
        }
    }

    // MARK: Catalog

    func requestOpenCatalog() {
        let panel = NSOpenPanel()
        panel.title = "Choose a CrossTie Catalog"
        panel.message = "Select a crossover.tie catalog file supplied by your CrossOver installation."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let defaultURL = CrossOverData.defaultTieURL() {
            panel.directoryURL = defaultURL.deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            openCatalog(url: url)
        }
    }

    func openDefaultCatalog() {
        guard let url = CrossOverData.defaultTieURL() else {
            showAlert(
                title: "No CrossOver catalog found",
                message: "Cork could not find crossover.tie in your CrossOver data directory. Choose a catalog file manually instead."
            )
            return
        }
        openCatalog(url: url)
    }

    func openCatalog(url: URL) {
        isCatalogLoading = true
        Task {
            do {
                let loaded = try await Task.detached {
                    try CrossTieCatalog(fileURL: url)
                }.value
                catalog = loaded
                catalogURL = url
                catalogCategories = loaded.categories()
                selectedCategory = nil
                catalogSearchText = ""
                selectedAppID = nil
                refreshCatalog()
            } catch {
                isCatalogLoading = false
                present(error, title: "Could not read catalog")
                return
            }
            isCatalogLoading = false
        }
    }

    func refreshCatalog() {
        guard let catalog else {
            catalogApps = []
            selectedAppID = nil
            return
        }
        let query = CatalogQuery(
            text: catalogSearchText,
            categories: selectedCategory.map { [$0] } ?? [],
            limit: 500
        )
        catalogApps = catalog.search(query)
        if let current = selectedAppID,
           catalogApps.contains(where: { $0.id == current }) {
            // Keep the current selection.
        } else {
            selectedAppID = catalogApps.first?.id
        }
    }

    // MARK: Install wizard

    /// Opens the install wizard for a catalog entry.
    func requestInstall(_ app: RecipeApp) {
        installAppID = app.id
        installAppName = app.name
        installExistingBottle = selectedBottleName ?? bottles.first?.name
        installCreateNewBottle = bottles.isEmpty
        installNewBottleName = Self.suggestBottleName(for: app.name)
        installLog = []
        isInstalling = false
        installOutcome = .running
        showInstallSheet = true
    }

    /// A bottle name derived from an app name that passes `Bottle.validateName`.
    static func suggestBottleName(for appName: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _.-")
        let filtered = String(appName.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
        var name = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "  ", with: " ")
        if name.isEmpty || name.hasPrefix(".") { name = "Bottle" }
        if name.count > 64 { name = String(name.prefix(64)) }
        if (try? Bottle.validateName(name)) == nil { name = "Bottle" }
        return name
    }

    /// True when the wizard has enough information to attempt an install.
    var installTargetIsValid: Bool {
        if installCreateNewBottle {
            let trimmed = installNewBottleName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (try? Bottle.validateName(trimmed)) != nil
        }
        return installExistingBottle.map { name in bottles.contains { $0.name == name } } ?? false
    }

    /// Runs the install on a background task, streaming `InstallEvent`s into the
    /// live log. Never blocks the UI thread.
    func startInstall() {
        guard bottleManager != nil else {
            installOutcome = .failed
            appendInstallLog("No bottle manager: \(startupError ?? "the runtime could not be loaded").")
            return
        }
        let targetBottle: String
        if installCreateNewBottle {
            targetBottle = installNewBottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            targetBottle = installExistingBottle ?? ""
        }
        guard !targetBottle.isEmpty else {
            installOutcome = .failed
            appendInstallLog("Choose a target bottle first.")
            return
        }

        isInstalling = true
        installOutcome = .running
        installLog = []
        appendInstallLog("Installing “\(installAppName)” into “\(targetBottle)”…")

        let appID = installAppID
        let appName = installAppName
        let catalogFile = catalogURL
        let createNew = installCreateNewBottle
        let paths = self.paths
        let box = bottleManager.map { UncheckedSendable($0) }

        Task {
            defer { self.isInstalling = false }
            do {
                // Resolve the recipe *before* creating a bottle: a catalog entry
                // with no automated install must not leave an empty bottle
                // behind.
                guard let catalogFile else {
                    throw CorkError.unsupported(reason: "no catalog is loaded, so there is no install recipe")
                }

                let recipes = try await Task.detached {
                    try CrossTieInstallRecipes(fileURL: catalogFile)
                }.value

                guard let recipe = recipes.installRecipe(appID: appID) else {
                    self.appendInstallLog("No automated install recipe is available for “\(appName)”.")
                    self.installOutcome = .noRecipe
                    return
                }

                if createNew {
                    guard let box else { throw CorkError.runtimeNotInstalled }
                    self.appendInstallLog("Creating bottle “\(targetBottle)”…")
                    _ = try await Task.detached { () -> Bottle in
                        try await box.value.create(
                            named: targetBottle,
                            settings: BottleSettings(),
                            onEvent: { event in
                                Task { @MainActor in self.appendInstallLog(Self.describe(event)) }
                            }
                        )
                    }.value
                    self.refreshBottles()
                    self.selectedBottleName = targetBottle
                }

                self.appendInstallLog("Executing \(recipe.steps.count) recipe step(s).")
                let installer = WineInstaller(paths: paths)
                try await Task.detached {
                    try await installer.install(recipe: recipe, into: targetBottle) { event in
                        Task { @MainActor in self.appendInstallLog(Self.describe(event)) }
                    }
                }.value

                self.appendInstallLog("Done — “\(appName)” finished installing.")
                self.installOutcome = .succeeded
                self.refreshBottles()
            } catch {
                let message = Self.describe(error)
                self.appendInstallLog("Failed: \(message)")
                self.installOutcome = .failed
            }
        }
    }

    func appendInstallLog(_ line: String) {
        installLog.append(line)
    }

    func closeInstallSheet() {
        guard !isInstalling else { return }
        showInstallSheet = false
    }

    nonisolated static func describe(_ event: InstallEvent) -> String {
        switch event {
        case .resolving(let detail):
            return "Resolving: \(detail)"
        case .downloading(let name, let totalBytes):
            if let totalBytes, totalBytes > 0 {
                return "Downloading \(name) (\(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)))…"
            }
            return "Downloading \(name)…"
        case .running(let command):
            return "Running: \(command)"
        case .copying(let detail):
            return "Copying: \(detail)"
        case .shortcut(let name):
            return "Creating shortcut: \(name)"
        case .registry(let detail):
            return "Applying registry: \(detail)"
        case .warning(let message):
            return "Warning: \(message)"
        case .finished:
            return "Recipe finished."
        }
    }

    // MARK: Bottle file browser

    /// The bottle whose `drive_c` is currently browsed.
    var filesBottle: Bottle? {
        if let name = filesBottleName, let match = bottles.first(where: { $0.name == name }) {
            return match
        }
        return selectedBottle
    }

    /// The directory represented by the current breadcrumb, if it exists.
    var browserDirectory: URL? {
        guard let bottle = filesBottle else { return nil }
        var url = bottle.driveCDirectory
        for component in browserComponents {
            url.appendPathComponent(component, isDirectory: true)
        }
        return url
    }

    func selectFilesBottle(_ name: String?) {
        programScanRevision += 1
        isDiscoveringPrograms = false
        filesBottleName = name
        browserComponents = []
        browserSelectedURL = nil
        discoveredPrograms = []
        refreshBrowser()
    }

    func refreshBrowser() {
        guard let directory = browserDirectory else {
            browserEntries = []
            return
        }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            browserEntries = []
            return
        }
        let entries = contents.map { url -> BrowserEntry in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return BrowserEntry(
                url: url,
                isDirectory: values?.isDirectory ?? false,
                size: Int64(values?.fileSize ?? 0)
            )
        }
        browserEntries = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func browserEnter(_ entry: BrowserEntry) {
        guard entry.isDirectory else {
            browserSelectedURL = entry.url
            return
        }
        browserComponents.append(entry.name)
        browserSelectedURL = nil
        refreshBrowser()
    }

    func browserGoUp() {
        guard !browserComponents.isEmpty else { return }
        browserComponents.removeLast()
        browserSelectedURL = nil
        refreshBrowser()
    }

    func browserGoTo(index: Int) {
        guard index < browserComponents.count else { return }
        browserComponents = Array(browserComponents.prefix(index))
        browserSelectedURL = nil
        refreshBrowser()
    }

    /// Scans the selected bottle's `drive_c` for `.exe` files (bounded depth) and
    /// merges the metadata pins, so the Installed Programs list is populated.
    func discoverPrograms() {
        guard let bottle = filesBottle else {
            present(CorkError.bottleNotFound(name: filesBottleName ?? ""), title: "Cannot scan bottle")
            return
        }
        programScanRevision += 1
        let revision = programScanRevision
        let targetName = bottle.name
        isDiscoveringPrograms = true
        let root = bottle.driveCDirectory
        let pins = bottle.metadata.pins

        Task {
            let found = await Task.detached { () -> [DiscoveredProgram] in
                BottleFiles.discoverExecutables(under: root, limit: 400)
            }.value
            guard revision == self.programScanRevision,
                  self.filesBottle?.name == targetName else { return }
            self.filesBottleName = targetName
            self.discoveredPrograms = BottleFiles.merge(pins: pins, discovered: found)
            self.isDiscoveringPrograms = false
        }
    }

    /// Programs known for a bottle without a full scan: metadata pins plus any
    /// previously discovered list when it belongs to the same bottle.
    func knownPrograms(for bottle: Bottle) -> [DiscoveredProgram] {
        if filesBottleName == bottle.name, !discoveredPrograms.isEmpty {
            return discoveredPrograms
        }
        return BottleFiles.merge(pins: bottle.metadata.pins, discovered: [])
    }

    // MARK: Program launch

    func launchProgram(bottleName: String, executable: URL, arguments: [String] = []) {
        guard let manager = bottleManager else {
            present(CorkError.runtimeNotInstalled, title: "Cannot run program")
            return
        }
        let box = UncheckedSendable(manager)
        Task {
            do {
                let status = try await Task.detached {
                    try box.value.run(
                        named: bottleName,
                        executable: executable,
                        arguments: arguments,
                        detach: true
                    )
                }.value
                alert = AppAlert(
                    title: "Run finished",
                    message: "\(executable.lastPathComponent) exited with status \(status)."
                )
            } catch {
                present(error, title: "Could not run \(executable.lastPathComponent)")
            }
        }
    }

    // MARK: App bundling

    /// Opens the bundle sheet for an executable inside a bottle.
    func requestBundle(bottleName: String, executable: URL) {
        bundleBottleName = bottleName
        bundleExecutableURL = executable
        bundleName = executable.deletingPathExtension().lastPathComponent
        bundleIconPath = nil
        bundleOutputDirectory = BottleFiles.defaultApplicationsDirectory
        bundleArguments = ""
        bundledAppURL = nil
        bundleError = nil
        showBundleSheet = true
    }

    func chooseBundleIcon() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Icon"
        panel.message = "Select an image (.icns, .png, .tiff, …) to use as the app icon."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            bundleIconPath = panel.url
        }
    }

    func chooseBundleOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.message = "Cork will create <name>.app in this folder."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = bundleOutputDirectory
        if panel.runModal() == .OK, let url = panel.url {
            bundleOutputDirectory = url
        }
    }

    var bundleIsValid: Bool {
        guard let executable = bundleExecutableURL, executable.pathExtension.lowercased() == "exe" else {
            return false
        }
        guard !bundleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !bundleBottleName.isEmpty else { return false }
        return true
    }

    func createBundle() {
        guard let executable = bundleExecutableURL else {
            bundleError = "No executable selected."
            return
        }
        guard let manager = bottleManager else {
            bundleError = CorkError.runtimeNotInstalled.errorDescription
            return
        }
        let name = bundleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let arguments = bundleArguments
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
        let icon = bundleIconPath
        let output = bundleOutputDirectory
        let bottleName = bundleBottleName

        isBundling = true
        bundleError = nil
        bundledAppURL = nil

        let box = UncheckedSendable(manager)
        Task {
            do {
                let url = try await Task.detached { () -> URL in
                    let bottle = try box.value.load(named: bottleName)
                    let bundler = AppBundler()
                    let created = try bundler.createBundle(
                        name: name,
                        bottle: bottle,
                        executable: executable.path,
                        arguments: arguments,
                        iconPath: icon,
                        outputDirectory: output
                    )
                    // Best-effort: apply the bottle's file-type associations.
                    _ = try? AssociationStore().registerInBundle(created, bottle: bottleName)
                    return created
                }.value
                self.bundledAppURL = url
                self.isBundling = false
            } catch {
                self.bundleError = Self.describe(error)
                self.isBundling = false
            }
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Dependencies

    /// Loads the built-in dependency catalog off the main thread and records
    /// which components can only be finished manually.
    func loadDependencies() {
        let manager = DependencyManager(paths: paths)
        Task {
            let result = await Task.detached { () -> ([DependencyComponent], Set<String>) in
                let components = manager.components()
                var manual: Set<String> = []
                for component in components {
                    guard let definition = manager.definition(id: component.id) else { continue }
                    if definition.steps.contains(where: { step in
                        if case .manual = step { return true }
                        return false
                    }) {
                        manual.insert(component.id)
                    }
                }
                return (components, manual)
            }.value

            self.dependencyComponents = result.0
            self.dependencyManualIDs = result.1
            if let current = self.selectedDependencyID,
               result.0.contains(where: { $0.id == current }) {
                // Keep the current selection.
            } else {
                self.selectedDependencyID = self.filteredDependencyComponents.first?.id
                    ?? result.0.first?.id
            }
        }
    }

    /// Opens the install sheet for a component, defaulting to the current bottle.
    func requestInstallDependency(_ component: DependencyComponent) {
        dependencyInstallComponentID = component.id
        dependencyInstallComponentName = component.name
        dependencyInstallBottle = selectedBottleName ?? bottles.first?.name
        dependencyInstallLog = []
        isInstallingDependency = false
        dependencyInstallOutcome = .running
        showDependencyInstallSheet = true
    }

    var dependencyInstallTargetIsValid: Bool {
        guard let name = dependencyInstallBottle else { return false }
        return bottles.contains { $0.name == name }
    }

    /// Runs a dependency install on a background task, streaming `InstallEvent`s
    /// into the live log. Never blocks the UI thread.
    func startDependencyInstall() {
        guard let targetBottle = dependencyInstallBottle, !targetBottle.isEmpty else {
            dependencyInstallOutcome = .failed
            appendDependencyLog("Choose a target bottle first.")
            return
        }
        let componentID = dependencyInstallComponentID
        isInstallingDependency = true
        dependencyInstallOutcome = .running
        dependencyInstallLog = []
        appendDependencyLog("Installing “\(dependencyInstallComponentName)” into “\(targetBottle)”…")

        let manager = DependencyManager(paths: paths)
        Task {
            defer { self.isInstallingDependency = false }
            do {
                try await Task.detached {
                    try await manager.install(
                        componentID: componentID,
                        into: targetBottle
                    ) { event in
                        Task { @MainActor in self.appendDependencyLog(Self.describe(event)) }
                    }
                }.value
                self.appendDependencyLog("Done — “\(self.dependencyInstallComponentName)” finished installing.")
                self.dependencyInstallOutcome = .succeeded
                self.refreshBottles()
            } catch {
                let message = Self.describe(error)
                self.appendDependencyLog("Failed: \(message)")
                self.dependencyInstallOutcome = .failed
            }
        }
    }

    func appendDependencyLog(_ line: String) {
        dependencyInstallLog.append(line)
    }

    func closeDependencyInstallSheet() {
        guard !isInstallingDependency else { return }
        showDependencyInstallSheet = false
    }

    // MARK: Diagnostics

    /// Runs the diagnostic engine for the currently selected bottle (or the host
    /// when "System" is chosen) off the main thread.
    func runDiagnostics() {
        isRunningDiagnostics = true
        let bottle = diagnosticBottle
        let diagnostics = Diagnostics(paths: paths)
        Task {
            let report = await Task.detached { () -> DiagnosticReport? in
                try? diagnostics.run(bottle: bottle)
            }.value
            self.diagnosticReport = report
            self.isRunningDiagnostics = false
            if let current = self.selectedDiagnosticCheckID,
               report?.checks.contains(where: { $0.id == current }) == true {
                // Keep the current selection.
            } else {
                self.selectedDiagnosticCheckID = report?.checks.first?.id
            }
        }
    }

    /// Human-readable label for the diagnostics target picker.
    var diagnosticTargetLabel: String {
        diagnosticBottle ?? "System"
    }

    var selectedDiagnosticCheck: DiagnosticCheck? {
        diagnosticReport?.checks.first { $0.id == selectedDiagnosticCheckID }
    }

    // MARK: File associations

    /// Loads the associations for a bottle, preparing the current selection.
    func loadAssociations(bottleName: String?) {
        associationsBottleName = bottleName
        associationsRegistryLines = []
        showAssociationsRegistry = false
        guard let bottleName else {
            associations = []
            return
        }
        let store = AssociationStore(paths: paths)
        Task {
            let entries = await Task.detached { () -> [AssociationEntry] in
                (try? store.read(bottle: bottleName)) ?? []
            }.value
            guard self.associationsBottleName == bottleName else { return }
            self.associations = entries
        }
    }

    /// Ensures associations are loaded for the detail pane's bottle.
    func ensureAssociationsLoaded(for bottleName: String) {
        if associationsBottleName != bottleName {
            loadAssociations(bottleName: bottleName)
        }
    }

    /// Opens the add-association form for a bottle.
    func requestAddAssociation(bottleName: String) {
        associationFormExtension = ""
        associationFormExecutable = ""
        associationFormProgID = ""
        associationFormFriendlyName = ""
        associationsBottleName = bottleName
        showAssociationSheet = true
    }

    /// True when the add-association form has enough to attempt a write.
    var associationFormIsValid: Bool {
        let ext = Self.normalizedExtension(associationFormExtension)
        let executable = associationFormExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        return !ext.isEmpty && !executable.isEmpty
    }

    /// Canonicalises a user-typed extension the way CorkEngine does: trimmed,
    /// lowercased, single leading dot. Empty when nothing usable remains.
    static func normalizedExtension(_ raw: String) -> String {
        var ext = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while ext.hasPrefix(".") { ext.removeFirst() }
        return ext.isEmpty ? "" : "." + ext
    }

    /// Persists the form as a new association and reloads the list.
    func addAssociation() {
        guard let bottleName = associationsBottleName else {
            present(CorkError.bottleNotFound(name: ""), title: "Cannot add association")
            return
        }
        guard associationFormIsValid else { return }

        let paths = self.paths
        let trimmedProgID = associationFormProgID.trimmingCharacters(in: .whitespacesAndNewlines)
        let friendly = associationFormFriendlyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = AssociationEntry(
            fileExtension: associationFormExtension,
            progID: trimmedProgID.isEmpty
                ? Self.generatedProgID(executable: associationFormExecutable)
                : trimmedProgID,
            friendlyName: friendly.isEmpty ? nil : friendly,
            executable: associationFormExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        applyAssociationChange(bottleName: bottleName, title: "Could not add association") {
            try AssociationStore(paths: paths).set(entry, bottle: bottleName)
        }
        showAssociationSheet = false
    }

    func removeAssociation(fileExtension: String) {
        guard let bottleName = associationsBottleName else { return }
        let paths = self.paths
        applyAssociationChange(bottleName: bottleName, title: "Could not remove association") {
            try AssociationStore(paths: paths).remove(fileExtension: fileExtension, bottle: bottleName)
        }
    }

    /// Loads (or hides) the registry command lines for the current bottle.
    func toggleAssociationsRegistry() {
        guard let bottleName = associationsBottleName else { return }
        if showAssociationsRegistry {
            showAssociationsRegistry = false
            associationsRegistryLines = []
            return
        }
        let store = AssociationStore(paths: paths)
        Task {
            let lines = await Task.detached { () -> [String] in
                (try? store.registryCommandLines(bottle: bottleName)) ?? []
            }.value
            guard self.associationsBottleName == bottleName else { return }
            self.associationsRegistryLines = lines
            self.showAssociationsRegistry = true
        }
    }

    /// Runs a mutating association operation off the main thread, reloading the
    /// list afterwards or reporting the error through the alert mechanism.
    private func applyAssociationChange(
        bottleName: String,
        title: String,
        _ operation: @escaping @Sendable () throws -> Void
    ) {
        let box = UncheckedSendable(operation)
        Task {
            do {
                try await Task.detached { try box.value() }.value
                self.loadAssociations(bottleName: bottleName)
            } catch {
                self.present(error, title: title)
            }
        }
    }

    /// Builds a stable ProgID from the program name, mirroring the CLI's rule.
    static func generatedProgID(executable: String) -> String {
        let normalized = executable
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        let base = (normalized as NSString).lastPathComponent
        let stem = (base as NSString).deletingPathExtension
        let name = stem.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        return "Cork\(name.isEmpty ? "App" : name)"
    }
}
