import SwiftUI
import CorkEngine

/// The detail pane for a selected catalog entry: every recipe field the
/// CorkEngine model exposes.
struct CatalogDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let app = model.selectedApp {
                detail(for: app)
            } else if model.catalog == nil {
                EmptyStateView(
                    icon: "square.grid.2x2",
                    title: "No Catalog Loaded",
                    message: "Open a CrossTie catalog to browse applications and view their install recipes."
                )
            } else if model.catalogIsEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "Catalog Is Empty",
                    message: "This catalog contains no application records, so there is nothing to show. This is expected while the CrossTie parser is still being implemented."
                )
            } else {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No Application Selected",
                    message: "Select an application from the list to see its recipe details."
                )
            }
        }
    }

    @ViewBuilder
    private func detail(for app: RecipeApp) -> some View {
        Form {
            Section("Application") {
                LabeledContent("Name", value: app.name)
                LabeledContent("Identifier", value: app.id)
                if let category = app.category {
                    LabeledContent("Category", value: category)
                }
                if let version = app.version {
                    LabeledContent("Version", value: version)
                }
            }

            Section("Compatibility") {
                HStack {
                    Text("Rating")
                    Spacer()
                    Text(stars(for: app.rating))
                        .foregroundStyle(medalColor(app.medal))
                    if let medal = app.medal, !medal.isEmpty {
                        Text(medal.capitalized)
                            .foregroundStyle(medalColor(app.medal))
                    }
                }
                LabeledContent("Medal", value: display(app.medal))
                LabeledContent("Medal platform", value: display(app.medalPlatform))
                LabeledContent("Bottle template", value: display(app.bottleTemplate))
                LabeledContent("Installer version", value: display(app.installerVersion))
                LabeledContent("Automated installer", value: app.hasInstaller ? "Yes" : "No")
                if !app.platforms.isEmpty {
                    LabeledContent("Platforms", value: app.platforms.joined(separator: ", "))
                }
            }

            Section("Dependencies") {
                if app.dependencies.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.dependencies, id: \.self) { dependency in
                        Text(dependency)
                            .font(.callout)
                    }
                }
            }

            Section("Default Associations") {
                if app.defaultAssociations.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.defaultAssociations, id: \.self) { association in
                        Label(association, systemImage: "doc")
                            .font(.callout)
                    }
                }
            }

            if let summary = app.summary, !summary.isEmpty {
                Section("Summary") {
                    Text(summary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let notes = app.installNotes, !notes.isEmpty {
                Section("Install Notes") {
                    Text(notes)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(app.name)
    }
}
