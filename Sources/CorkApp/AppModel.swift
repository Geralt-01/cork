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

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bottles: return "Bottles"
            case .applications: return "Applications"
            }
        }

        var systemImage: String {
            switch self {
            case .bottles: return "shippingbox"
            case .applications: return "square.grid.2x2"
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
    func applySetting(_ bottleName: String, key: BottleSettings.Key, value: String) {
        if let index = bottles.firstIndex(where: { $0.name == bottleName }) {
            try? bottles[index].metadata.settings.apply(key: key.rawValue, value: value)
        }

        guard let manager = bottleManager else { return }
        let box = UncheckedSendable(manager)
        Task {
            do {
                let updated = try await Task.detached {
                    try box.value.setSetting(named: bottleName, key: key.rawValue, value: value)
                }.value
                if let index = bottles.firstIndex(where: { $0.name == bottleName }) {
                    bottles[index] = updated
                }
            } catch {
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
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            logsText = text
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
}
