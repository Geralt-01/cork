import SwiftUI
import AppKit

@main
struct CorkApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Bottle…") {
                    model.requestCreateBottle()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!model.isWineReady)

                Button("Open Catalog…") {
                    model.requestOpenCatalog()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("View") {
                Button("Bottles") {
                    model.section = .bottles
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Applications") {
                    model.section = .applications
                }
                .keyboardShortcut("2", modifiers: .command)

                Divider()

                Button("Refresh") {
                    model.refreshAll()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

/// Three-column shell: sections, a contextual list, and a detail pane.
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    private var section: AppModel.Section { model.section ?? .bottles }

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            switch section {
            case .bottles:
                BottlesView()
            case .applications:
                CatalogView()
            }
        } detail: {
            switch section {
            case .bottles:
                BottleDetailView()
            case .applications:
                CatalogDetailView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $model.showCreateSheet) {
            CreateBottleSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: logsPresented) {
            LogsSheet(
                title: model.logsBottleName.map { "Logs — \($0)" } ?? "Logs",
                text: model.logsText
            )
        }
    }

    private var logsPresented: Binding<Bool> {
        Binding(
            get: { model.logsBottleName != nil },
            set: { if !$0 { model.logsBottleName = nil } }
        )
    }
}

/// Sidebar listing the top-level sections and the live Wine runtime status.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.section) {
            Section("Library") {
                ForEach(AppModel.Section.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(Optional(section))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Cork")
        .frame(minWidth: 190)
        .safeAreaInset(edge: .bottom) {
            runtimeStatus
        }
    }

    private var runtimeStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isWineReady ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(model.isWineReady ? "Wine runtime ready" : "Wine runtime not installed")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// A sheet that displays a log file's contents.
struct LogsSheet: View {
    let title: String
    let text: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollView {
                Text(text.isEmpty ? "(empty log)" : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
