import SwiftUI
import CorkKit

/// The content column for the Bottles section: the list of bottles plus the
/// actions that operate on the current selection.
struct BottlesView: View {
    @EnvironmentObject private var model: AppModel
    // `@State` is implemented by a compiler macro that ships with Xcode. Cork
    // also supports building with only the Command Line Tools, where that macro
    // plugin is unavailable, so view-local state uses `@StateObject` instead.
    @StateObject private var ui = BottlesViewState()

    var body: some View {
        Group {
            if model.bottles.isEmpty && model.bottleIssues.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Bottles",
                    message: wineMessage
                ) {
                    Button {
                        model.requestCreateBottle()
                    } label: {
                        Label("Create Bottle", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.isWineReady)
                }
            } else {
                List(selection: $model.selectedBottleName) {
                    Section("Bottles") {
                        ForEach(model.bottles) { bottle in
                            BottleRow(bottle: bottle)
                                .tag(Optional(bottle.name))
                        }
                    }
                    if !model.bottleIssues.isEmpty {
                        Section("Problems") {
                            ForEach(model.bottleIssues, id: \.directoryName) { issue in
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(issue.directoryName, systemImage: "exclamationmark.triangle")
                                        .font(.callout)
                                    Text(issue.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Bottles")
        .frame(minWidth: 240)
        .toolbar { toolbarContent }
        .alert("Delete Bottle?", isPresented: deletePresented, presenting: ui.pendingDelete) { name in
            Button("Delete", role: .destructive) {
                model.requestDelete(name)
                ui.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { ui.pendingDelete = nil }
        } message: { name in
            Text("This permanently removes “\(name)” and its Windows prefix. This cannot be undone.")
        }
    }

    private var wineMessage: String {
        model.isWineReady
            ? "Create your first bottle to get started."
            : "The Wine runtime isn't installed yet. Run “cork runtime install” to enable creating bottles; you can still browse existing ones."
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { ui.pendingDelete != nil },
            set: { if !$0 { ui.pendingDelete = nil } }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.requestCreateBottle()
            } label: {
                Label("Create Bottle", systemImage: "plus")
            }
            .help("Create a new bottle")
            .disabled(!model.isWineReady)

            Button {
                if let name = model.selectedBottleName {
                    model.chooseAndRun(bottleName: name)
                }
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .help("Run a Windows executable in the selected bottle")
            .disabled(model.selectedBottleName == nil || !model.isWineReady)

            Button {
                if let name = model.selectedBottleName {
                    model.kill(bottleName: name)
                }
            } label: {
                Label("Kill", systemImage: "stop.fill")
            }
            .help("Stop all Windows processes in the selected bottle")
            .disabled(model.selectedBottleName == nil)

            Button {
                if let name = model.selectedBottleName {
                    model.loadLogs(bottleName: name)
                }
            } label: {
                Label("Show Logs", systemImage: "doc.text.magnifyingglass")
            }
            .help("Show the most recent log for the selected bottle")
            .disabled(model.selectedBottleName == nil)

            Button {
                ui.pendingDelete = model.selectedBottleName
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete the selected bottle")
            .disabled(model.selectedBottleName == nil)

            Button {
                model.refreshBottles()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload the bottle list")
        }
    }
}

/// View-local state for `BottlesView`. See the note on `@StateObject` usage in
/// the view: this type keeps the code buildable without Xcode's SwiftUI macro
/// plugin.
final class BottlesViewState: ObservableObject {
    @Published var pendingDelete: String?
}

/// A compact summary row for one bottle.
struct BottleRow: View {
    let bottle: Bottle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(bottle.name)
                .font(.headline)
            HStack(spacing: 6) {
                Text(bottle.settings.windowsVersion.displayName)
                Text("•")
                Text(bottle.settings.backend.displayName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
