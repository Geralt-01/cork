import SwiftUI
import CorkKit
import CorkEngine

/// Sheet that installs a catalog application into a bottle. The user picks an
/// existing bottle or creates one inline; on confirm, the recipe executes on a
/// background task while events stream into the log below.
struct InstallWizardSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            targetSection

            if !model.installLog.isEmpty {
                progressView
            }

            if !model.isWineReady {
                Label(
                    "The Wine runtime isn't installed. Creating a bottle or running the installer will fail.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(20)
        .frame(width: 560, height: 560)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Install “\(model.installAppName)”")
                .font(.title2)
                .bold()
                .lineLimit(2)
            Text("Identifier: \(model.installAppID)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var targetSection: some View {
        Form {
            Section("Destination") {
                Toggle("Create a new bottle", isOn: $model.installCreateNewBottle)
                    .disabled(model.isInstalling)

                if model.installCreateNewBottle {
                    LabeledContent("New bottle name") {
                        TextField("Bottle name", text: $model.installNewBottleName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.isInstalling)
                    }
                } else {
                    LabeledContent("Bottle") {
                        if model.bottles.isEmpty {
                            Text("No bottles available")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("", selection: $model.installExistingBottle) {
                                ForEach(model.bottles) { bottle in
                                    Text(bottle.name).tag(Optional(bottle.name))
                                }
                            }
                            .labelsHidden()
                            .disabled(model.isInstalling)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 150)
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if model.isInstalling {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: outcomeIcon)
                        .foregroundStyle(outcomeColor)
                }
                Text(outcomeTitle)
                    .font(.callout)
                    .bold()
                Spacer()
                Text("\(model.installLog.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.installLog.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(6)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: model.installLog.count) { count in
                    guard count > 0 else { return }
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.installOutcome == .noRecipe {
                Label("No automated installer for this app.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            if model.isInstalling {
                Button("Cancel", role: .cancel) { }
                    .disabled(true)
                    .help("Installing cannot be interrupted safely.")
                Button("Installing…") { }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            } else if model.installIsTerminal {
                Button("Close") { model.closeInstallSheet() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Cancel") { model.closeInstallSheet() }
                    .keyboardShortcut(.cancelAction)
                Button("Install") { model.startInstall() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.installTargetIsValid)
            }
        }
    }

    // MARK: Outcome helpers

    private var outcomeTitle: String {
        switch model.installOutcome {
        case .running: return "Working…"
        case .succeeded: return "Install finished"
        case .failed: return "Install failed"
        case .noRecipe: return "Nothing to install"
        }
    }

    private var outcomeIcon: String {
        switch model.installOutcome {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .noRecipe: return "info.circle.fill"
        case .running: return "clock"
        }
    }

    private var outcomeColor: Color {
        switch model.installOutcome {
        case .succeeded: return .green
        case .failed: return .red
        case .noRecipe: return .orange
        case .running: return .secondary
        }
    }
}

private extension AppModel {
    /// The wizard shows a terminal footer once the run has stopped.
    var installIsTerminal: Bool {
        !isInstalling && installOutcome != .running
    }
}
