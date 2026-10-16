import SwiftUI
import CorkKit
import CorkEngine

/// Sheet that installs a dependency component into an existing bottle. On
/// confirm the component's recipe executes on a background task while
/// `InstallEvent`s stream into the log, mirroring the install wizard's style.
struct DependencyInstallSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            targetSection

            if !model.dependencyInstallLog.isEmpty {
                progressView
            }

            if !model.isWineReady {
                Label(
                    "The Wine runtime isn't installed. Installing a component will fail.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(20)
        .frame(width: 560, height: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Install “\(model.dependencyInstallComponentName)”")
                .font(.title2)
                .bold()
                .lineLimit(2)
            Text("Component: \(model.dependencyInstallComponentID)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        Form {
            Section("Destination") {
                LabeledContent("Bottle") {
                    if model.bottles.isEmpty {
                        Text("No bottles available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("", selection: $model.dependencyInstallBottle) {
                            ForEach(model.bottles) { bottle in
                                Text(bottle.name).tag(Optional(bottle.name))
                            }
                        }
                        .labelsHidden()
                        .disabled(model.isInstallingDependency)
                    }
                }

                if model.dependencyRequiresManual(model.dependencyInstallComponentID) {
                    Label(
                        "This component can only be finished manually; installing reports the steps.",
                        systemImage: "hand.raised.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: model.dependencyRequiresManual(model.dependencyInstallComponentID) ? 160 : 120)
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if model.isInstallingDependency {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: outcomeIcon)
                        .foregroundStyle(outcomeColor)
                }
                Text(outcomeTitle)
                    .font(.callout)
                    .bold()
                Spacer()
                Text("\(model.dependencyInstallLog.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.dependencyInstallLog.enumerated()), id: \.offset) { index, line in
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
                .onChange(of: model.dependencyInstallLog.count) { count in
                    guard count > 0 else { return }
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if model.isInstallingDependency {
                Button("Cancel", role: .cancel) { }
                    .disabled(true)
                    .help("Installing cannot be interrupted safely.")
                Button("Installing…") { }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            } else if isTerminal {
                Button("Close") { model.closeDependencyInstallSheet() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Cancel") { model.closeDependencyInstallSheet() }
                    .keyboardShortcut(.cancelAction)
                Button("Install") { model.startDependencyInstall() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.dependencyInstallTargetIsValid)
            }
        }
    }

    private var isTerminal: Bool {
        !model.isInstallingDependency && model.dependencyInstallOutcome != .running
    }

    private var outcomeTitle: String {
        switch model.dependencyInstallOutcome {
        case .running: return "Working…"
        case .succeeded: return "Install finished"
        case .failed: return "Install failed"
        case .noRecipe: return "Nothing to install"
        }
    }

    private var outcomeIcon: String {
        switch model.dependencyInstallOutcome {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .noRecipe: return "info.circle.fill"
        case .running: return "clock"
        }
    }

    private var outcomeColor: Color {
        switch model.dependencyInstallOutcome {
        case .succeeded: return .green
        case .failed: return .red
        case .noRecipe: return .orange
        case .running: return .secondary
        }
    }
}
