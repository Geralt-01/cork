import SwiftUI
import AppKit
import CorkKit

/// The detail pane for a selected bottle: an editor for every persisted
/// setting plus quick facts about the bottle.
struct BottleDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let bottle = model.selectedBottle {
                editor(for: bottle)
            } else {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Bottle Selected",
                    message: "Select a bottle from the list, or create a new one to configure its Windows version, graphics backend and performance options."
                )
            }
        }
    }

    @ViewBuilder
    private func editor(for bottle: Bottle) -> some View {
        Form {
            Section("Overview") {
                LabeledContent("Name", value: bottle.name)
                LabeledContent("Windows version", value: bottle.settings.windowsVersion.displayName)
                LabeledContent("Graphics backend", value: bottle.settings.backend.displayName)
                LabeledContent("Wine version", value: bottle.metadata.wineVersion)

                HStack {
                    Text("Location")
                    Spacer()
                    Text(bottle.url.path)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
            }

            Section("Graphics") {
                Picker("Backend", selection: backendBinding(bottle)) {
                    ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                Text(bottle.settings.backend.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Windows") {
                Picker("Version", selection: windowsBinding(bottle)) {
                    ForEach(WindowsVersion.allCases, id: \.self) { version in
                        Text(version.displayName).tag(version)
                    }
                }
            }

            Section("Synchronization") {
                Toggle("MSync", isOn: boolBinding(bottle, key: .msync) { $0.msync })
                Toggle("ESync", isOn: boolBinding(bottle, key: .esync) { $0.esync })
            }

            Section("Extras") {
                Toggle("DXVK async", isOn: boolBinding(bottle, key: .dxvkAsync) { $0.dxvkAsync })
                Toggle("Metal HUD", isOn: boolBinding(bottle, key: .metalHud) { $0.metalHUD })

                LabeledContent("DXVK HUD") {
                    TextField("off", text: textBinding(bottle, key: .dxvkHud) { $0.dxvkHUD ?? "" })
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 200)
                }
                LabeledContent("Debug channels") {
                    TextField("off", text: textBinding(bottle, key: .debug) { $0.debugChannels })
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 200)
                }
                Text("Leave DXVK HUD empty for “off”. Debug channels use Wine's channels syntax, e.g. fixme-all.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Logs") {
                HStack {
                    Text(latestLogName(bottle))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        model.loadLogs(bottleName: bottle.name)
                    } label: {
                        Label("Show Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(bottle.latestLogFile() == nil)
                }
            }

            AssociationsSection(bottle: bottle)
        }
        .formStyle(.grouped)
        .navigationTitle(bottle.name)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.chooseAndRun(bottleName: bottle.name)
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(!model.isWineReady)

                Button {
                    model.kill(bottleName: bottle.name)
                } label: {
                    Label("Kill", systemImage: "stop.fill")
                }
            }
        }
    }

    private func latestLogName(_ bottle: Bottle) -> String {
        bottle.latestLogFile()?.lastPathComponent ?? "No logs yet"
    }

    // MARK: Bindings (optimistic, persisted by the model)

    private func backendBinding(_ bottle: Bottle) -> Binding<GraphicsBackend> {
        Binding(
            get: { model.bottles.first { $0.name == bottle.name }?.settings.backend ?? bottle.settings.backend },
            set: { model.setBackend(bottle.name, $0) }
        )
    }

    private func windowsBinding(_ bottle: Bottle) -> Binding<WindowsVersion> {
        Binding(
            get: { model.bottles.first { $0.name == bottle.name }?.settings.windowsVersion ?? bottle.settings.windowsVersion },
            set: { model.setWindows(bottle.name, $0) }
        )
    }

    private func boolBinding(
        _ bottle: Bottle,
        key: BottleSettings.Key,
        _ value: @escaping (BottleSettings) -> Bool
    ) -> Binding<Bool> {
        Binding(
            get: {
                if let current = model.bottles.first(where: { $0.name == bottle.name }) {
                    return value(current.settings)
                }
                return value(bottle.settings)
            },
            set: { model.setToggle(bottle.name, key: key, $0) }
        )
    }

    private func textBinding(
        _ bottle: Bottle,
        key: BottleSettings.Key,
        _ value: @escaping (BottleSettings) -> String
    ) -> Binding<String> {
        Binding(
            get: {
                if let current = model.bottles.first(where: { $0.name == bottle.name }) {
                    return value(current.settings)
                }
                return value(bottle.settings)
            },
            set: { model.setText(bottle.name, key: key, $0) }
        )
    }
}
