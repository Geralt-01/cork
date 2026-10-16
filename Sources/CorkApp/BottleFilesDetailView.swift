import SwiftUI
import AppKit
import CorkKit

/// Detail column for the "Bottle Files" section: the selected file's actions
/// plus the bottle's installed/known programs with Launch and Bundle actions.
struct BottleFilesDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let bottle = model.filesBottle {
                content(for: bottle)
            } else {
                EmptyStateView(
                    icon: "folder",
                    title: "No Bottle Selected",
                    message: "Pick a bottle in the list to browse its drive_c and list its installed programs."
                )
            }
        }
    }

    @ViewBuilder
    private func content(for bottle: Bottle) -> some View {
        Form {
            selectedFileSection(bottle)
            installedProgramsSection(bottle)
        }
        .formStyle(.grouped)
        .navigationTitle(bottle.name)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    if let url = model.browserSelectedURL {
                        model.launchProgram(bottleName: bottle.name, executable: url)
                    }
                } label: {
                    Label("Launch", systemImage: "play.fill")
                }
                .disabled(!selectedIsExecutable || !model.isWineReady)
                .help("Run the selected executable in this bottle")

                Button {
                    if let url = model.browserSelectedURL {
                        model.requestBundle(bottleName: bottle.name, executable: url)
                    }
                } label: {
                    Label("Create macOS App", systemImage: "app.badge")
                }
                .disabled(!selectedIsExecutable)
                .help("Bundle the selected executable as a macOS app")

                Button {
                    model.discoverPrograms()
                } label: {
                    Label("Scan for Programs", systemImage: "magnifyingglass")
                }
                .disabled(model.isDiscoveringPrograms)
                .help("Scan drive_c for installed .exe programs")
            }
        }
    }

    private var selectedIsExecutable: Bool {
        guard let url = model.browserSelectedURL else { return false }
        return url.pathExtension.lowercased() == "exe"
    }

    // MARK: Selected file

    @ViewBuilder
    private func selectedFileSection(_ bottle: Bottle) -> some View {
        Section("Selected File") {
            if let url = model.browserSelectedURL {
                LabeledContent("Name", value: url.lastPathComponent)
                LabeledContent("Location") {
                    Text(url.deletingLastPathComponent().path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button {
                        model.launchProgram(bottleName: bottle.name, executable: url)
                    } label: {
                        Label("Launch", systemImage: "play.fill")
                    }
                    .disabled(!selectedIsExecutable || !model.isWineReady)

                    Button {
                        model.requestBundle(bottleName: bottle.name, executable: url)
                    } label: {
                        Label("Create macOS App…", systemImage: "app.badge")
                    }
                    .disabled(!selectedIsExecutable)

                    Button {
                        model.revealInFinder(url)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Spacer()
                }
                if !selectedIsExecutable {
                    Text("Only .exe files can be launched or bundled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select a file in the browser.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Installed programs

    @ViewBuilder
    private func installedProgramsSection(_ bottle: Bottle) -> some View {
        Section("Installed Programs") {
            if model.isDiscoveringPrograms {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning drive_c for executables…")
                        .foregroundStyle(.secondary)
                }
            } else if model.knownPrograms(for: bottle).isEmpty {
                Text("No programs are known for this bottle yet.")
                    .foregroundStyle(.secondary)
                Button {
                    model.discoverPrograms()
                } label: {
                    Label("Scan drive_c for .exe", systemImage: "magnifyingglass")
                }
            } else {
                ForEach(model.knownPrograms(for: bottle)) { program in
                    ProgramRow(program: program, bottle: bottle)
                }
            }
        }
    }
}

/// A single known program with Launch / Bundle actions.
private struct ProgramRow: View {
    @EnvironmentObject private var model: AppModel
    let program: DiscoveredProgram
    let bottle: Bottle

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "app.fill")
                .foregroundStyle(.blue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(program.name)
                    .lineLimit(1)
                Text(program.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(program.origin.label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                model.launchProgram(
                    bottleName: bottle.name,
                    executable: program.url,
                    arguments: program.arguments
                )
            } label: {
                Label("Launch", systemImage: "play.fill")
            }
            .disabled(!model.isWineReady)
            .help(model.isWineReady ? "Run in this bottle" : "The Wine runtime isn't installed")

            Button {
                model.requestBundle(bottleName: bottle.name, executable: program.url)
            } label: {
                Label("Bundle…", systemImage: "app.badge")
            }
            .help("Create a macOS app for this program")
        }
        .padding(.vertical, 2)
    }
}
