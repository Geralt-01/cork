import SwiftUI
import CorkEngine

/// The content column for the Applications section: a catalog browser with a
/// search field, category filter, and results list.
struct CatalogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.catalog == nil {
                noCatalogState
            } else if model.catalogIsEmpty {
                emptyCatalogState
            } else {
                resultsList
            }
        }
        .navigationTitle("Applications")
        .frame(minWidth: 280)
        .toolbar { toolbarContent }
    }

    // MARK: Empty states

    private var noCatalogState: some View {
        EmptyStateView(
            icon: "square.grid.2x2",
            title: "No Catalog Loaded",
            message: "Choose a CrossTie catalog file to browse installable applications. Cork never bundles this data — it uses a catalog you supply."
        ) {
            VStack(spacing: 8) {
                Button {
                    model.openDefaultCatalog()
                } label: {
                    Label("Use CrossOver Catalog", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.requestOpenCatalog()
                } label: {
                    Label("Choose Catalog…", systemImage: "folder")
                }
                .disabled(model.isCatalogLoading)
            }
        }
    }

    private var emptyCatalogState: some View {
        EmptyStateView(
            icon: "tray",
            title: "Catalog Is Empty",
            message: "“\(model.catalog?.sourceDescription ?? "catalog")” loaded successfully but contains 0 applications. The CrossTie parser may still be under development; try a different catalog file."
        ) {
            Button {
                model.requestOpenCatalog()
            } label: {
                Label("Choose Another Catalog…", systemImage: "folder")
            }
            .disabled(model.isCatalogLoading)
        }
    }

    // MARK: Results

    private var resultsList: some View {
        VStack(spacing: 0) {
            header
            Divider()
            categoryFilter
            Divider()
            list
        }
        .searchable(text: $model.catalogSearchText, prompt: "Search applications")
        .onChange(of: model.catalogSearchText) { _ in model.refreshCatalog() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.catalog?.sourceDescription ?? "Catalog")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(model.catalog?.appCount ?? 0) applications in catalog · \(model.catalogApps.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isCatalogLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var categoryFilter: some View {
        HStack {
            Picker("Category", selection: $model.selectedCategory) {
                Text("All Categories").tag(String?.none)
                ForEach(model.catalogCategories, id: \.self) { category in
                    Text(category).tag(String?.some(category))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: model.selectedCategory) { _ in model.refreshCatalog() }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var list: some View {
        if model.catalogApps.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No Matches",
                message: "No applications matched your search or category filter."
            )
        } else {
            List(selection: $model.selectedAppID) {
                ForEach(model.catalogApps) { app in
                    CatalogRow(app: app)
                        .tag(Optional(app.id))
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.requestOpenCatalog()
            } label: {
                Label("Open Catalog", systemImage: "folder")
            }
            .help("Choose a CrossTie catalog file")
            .disabled(model.isCatalogLoading)

            Button {
                model.openDefaultCatalog()
            } label: {
                Label("Use CrossOver Catalog", systemImage: "wand.and.stars")
            }
            .help("Load the catalog from your CrossOver installation, if present")
            .disabled(model.isCatalogLoading)

            Button {
                model.refreshCatalog()
            } label: {
                Label("Refresh Results", systemImage: "arrow.clockwise")
            }
            .help("Re-run the current search")
        }
    }
}

/// A single search result row.
struct CatalogRow: View {
    let app: RecipeApp

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(app.name)
                    .font(.headline)
                    .lineLimit(1)
                if app.hasInstaller {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .help("Has an automated installer")
                }
            }
            if let summary = app.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(app.category ?? "Uncategorized")
                    .lineLimit(1)
                Text("·")
                Text(stars(for: app.rating))
                    .foregroundStyle(medalColor(app.medal))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
