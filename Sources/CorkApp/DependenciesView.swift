import SwiftUI
import CorkEngine

/// The content column for the Dependencies section: Cork's built-in
/// winetricks-style component catalog with a category filter and search.
struct DependenciesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.dependencyComponents.isEmpty {
                EmptyStateView(
                    icon: "puzzlepiece.extension",
                    title: "No Components",
                    message: "Cork ships a built-in set of dependency components (runtimes, DirectX, libraries and fonts). None were found in this build."
                )
            } else {
                VStack(spacing: 0) {
                    header
                    Divider()
                    categoryFilter
                    Divider()
                    list
                }
                .searchable(text: $model.dependencySearchText, prompt: "Search components")
            }
        }
        .navigationTitle("Dependencies")
        .frame(minWidth: 280)
        .toolbar { toolbarContent }
        .onAppear { model.loadDependencies() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dependency Components")
                    .font(.headline)
                Text("\(model.dependencyComponents.count) available · \(model.filteredDependencyComponents.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var categoryFilter: some View {
        HStack {
            Picker("Category", selection: $model.selectedDependencyCategory) {
                Text("All Categories").tag(String?.none)
                ForEach(model.dependencyCategories, id: \.self) { category in
                    Text(category).tag(String?.some(category))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var list: some View {
        if model.filteredDependencyComponents.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No Matches",
                message: "No dependency components matched your search or category filter."
            )
        } else {
            List(selection: $model.selectedDependencyID) {
                ForEach(model.filteredDependencyComponents, id: \.id) { component in
                    DependencyRow(
                        component: component,
                        requiresManual: model.dependencyRequiresManual(component.id)
                    )
                    .tag(Optional(component.id))
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.loadDependencies()
            } label: {
                Label("Reload Components", systemImage: "arrow.clockwise")
            }
            .help("Reload the built-in dependency catalog")
        }
    }
}

/// A single dependency component row.
struct DependencyRow: View {
    let component: DependencyComponent
    let requiresManual: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(component.name)
                    .font(.headline)
                    .lineLimit(1)
                if requiresManual {
                    Image(systemName: "hand.raised.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Requires manual installation")
                } else if component.requiresDownload {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .help("Downloads payloads from the network")
                }
            }
            if let summary = component.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(component.id)
                    .font(.system(.caption2, design: .monospaced))
                Text("·")
                Text(component.category)
                Text("·")
                Text(component.requiresDownload ? "Download" : "No download")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// The detail pane for a selected dependency component: its metadata and the
/// Install action that streams progress into a sheet.
struct DependenciesDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let component = model.selectedDependency {
                detail(for: component)
            } else {
                EmptyStateView(
                    icon: "puzzlepiece.extension",
                    title: "No Component Selected",
                    message: "Select a dependency component to see what it installs and to install it into a bottle."
                )
            }
        }
    }

    @ViewBuilder
    private func detail(for component: DependencyComponent) -> some View {
        let requiresManual = model.dependencyRequiresManual(component.id)
        Form {
            Section("Install") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if requiresManual {
                            Label("This component requires manual installation.", systemImage: "hand.raised.fill")
                                .foregroundStyle(.orange)
                                .font(.callout)
                            Text("Cork cannot unpack its payload automatically; installing it will report the manual steps.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Cork installs this component into a bottle you choose.")
                                .font(.callout)
                            Text(component.requiresDownload
                                 ? "This component downloads payloads from the network."
                                 : "This component needs no downloads.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        model.requestInstallDependency(component)
                    } label: {
                        Label("Install…", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.bottles.isEmpty)
                    .help(model.bottles.isEmpty
                          ? "Create a bottle first"
                          : "Install “\(component.name)” into a bottle")
                }
            }

            Section("Component") {
                LabeledContent("Name", value: component.name)
                LabeledContent("Identifier", value: component.id)
                LabeledContent("Category", value: component.category)
                LabeledContent("Download", value: component.requiresDownload ? "Required" : "None")
                LabeledContent("Manual steps", value: requiresManual ? "Required" : "Not required")
            }

            if let summary = component.summary, !summary.isEmpty {
                Section("Summary") {
                    Text(summary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Recipe Steps") {
                if component.verbs.isEmpty {
                    Text("No step information.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(component.verbs, id: \.self) { verb in
                        Label(verb, systemImage: stepIcon(verb))
                            .font(.callout)
                    }
                }
            }

            if !component.windowsVersions.isEmpty {
                Section("Windows Versions") {
                    Text(component.windowsVersions.joined(separator: ", "))
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(component.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.requestInstallDependency(component)
                } label: {
                    Label("Install", systemImage: "arrow.down.circle")
                }
                .disabled(model.bottles.isEmpty)
                .help(model.bottles.isEmpty
                      ? "Create a bottle first"
                      : "Install “\(component.name)” into a bottle")
            }
        }
    }

    private func stepIcon(_ verb: String) -> String {
        switch verb {
        case "download": return "arrow.down.circle"
        case "runInstaller", "runCommand": return "gearshape"
        case "registry": return "list.bullet.rectangle"
        case "copyFile": return "doc.on.doc"
        case "createDirectory": return "folder.badge.plus"
        case "setWindowsVersion": return "window"
        case "manual": return "hand.raised"
        default: return "circle"
        }
    }
}
