import SwiftUI
import AppKit
import CorkKit

/// Content column for the "Bottle Files" section: a `drive_c` browser for the
/// chosen bottle with breadcrumbs and an Up action.
struct BottleFilesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.bottles.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "No Bottles",
                    message: "Create a bottle first, then browse its Windows drive_c here."
                )
            } else {
                VStack(spacing: 0) {
                    bottlePicker
                    Divider()
                    breadcrumbs
                    Divider()
                    fileList
                }
            }
        }
        .navigationTitle("Bottle Files")
        .frame(minWidth: 280)
        .toolbar { toolbarContent }
        .onAppear {
            if model.filesBottleName == nil {
                model.selectFilesBottle(model.selectedBottleName ?? model.bottles.first?.name)
            } else {
                model.refreshBrowser()
            }
        }
    }

    // MARK: Bottle picker

    private var bottlePicker: some View {
        HStack {
            Picker("Bottle", selection: filesBottleBinding) {
                ForEach(model.bottles) { bottle in
                    Text(bottle.name).tag(Optional(bottle.name))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer()
            if let bottle = model.filesBottle {
                Text(bottle.settings.windowsVersion.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var filesBottleBinding: Binding<String?> {
        Binding(
            get: { model.filesBottle?.name },
            set: { model.selectFilesBottle($0) }
        )
    }

    // MARK: Breadcrumbs

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button("drive_c") { model.browserGoTo(index: 0) }
                    .buttonStyle(.link)
                    .disabled(model.browserComponents.isEmpty)

                ForEach(Array(model.browserComponents.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button(component) { model.browserGoTo(index: index + 1) }
                        .buttonStyle(.link)
                        .disabled(index == model.browserComponents.count - 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: Files

    @ViewBuilder
    private var fileList: some View {
        if model.browserEntries.isEmpty {
            EmptyStateView(
                icon: "tray",
                title: "Empty Folder",
                message: model.browserDirectory?.path ?? "This folder has no contents."
            )
        } else {
            List(selection: $model.browserSelectedURL) {
                ForEach(model.browserEntries) { entry in
                    BrowserRow(entry: entry)
                        .tag(Optional(entry.url))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.browserEnter(entry) }
                        .contextMenu {
                            if entry.isDirectory {
                                Button("Open") { model.browserEnter(entry) }
                            } else if entry.isExecutable, let bottle = model.filesBottle {
                                Button("Launch") {
                                    model.launchProgram(bottleName: bottle.name, executable: entry.url)
                                }
                                .disabled(!model.isWineReady)
                                Button("Create macOS App…") {
                                    model.requestBundle(bottleName: bottle.name, executable: entry.url)
                                }
                            }
                            Button("Reveal in Finder") { model.revealInFinder(entry.url) }
                        }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.browserGoUp()
            } label: {
                Label("Enclosing Folder", systemImage: "arrow.up")
            }
            .help("Go to the enclosing folder")
            .disabled(model.browserComponents.isEmpty)

            Button {
                model.refreshBrowser()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload the current folder")
            .disabled(model.filesBottle == nil)

            Button {
                model.discoverPrograms()
            } label: {
                Label("Discover Programs", systemImage: "magnifyingglass")
            }
            .help("Scan drive_c for Windows executables")
            .disabled(model.filesBottle == nil || model.isDiscoveringPrograms)
        }
    }
}

/// One row in the `drive_c` browser.
struct BrowserRow: View {
    let entry: BrowserEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if !entry.isDirectory, entry.size > 0 {
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }

    private var icon: String {
        if entry.isDirectory { return "folder.fill" }
        if entry.isExecutable { return "app.fill" }
        return "doc"
    }

    private var tint: Color {
        if entry.isDirectory { return .accentColor }
        if entry.isExecutable { return .blue }
        return .secondary
    }
}
