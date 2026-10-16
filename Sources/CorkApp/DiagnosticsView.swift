import SwiftUI
import CorkEngine

/// Local presentation mapping for a diagnostic status: a glyph and a colour.
extension DiagnosticStatus {
    var guiSymbol: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .skipped: return "minus.circle"
        }
    }

    var guiColor: Color {
        switch self {
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        case .skipped: return .secondary
        }
    }

    var guiLabel: String {
        switch self {
        case .pass: return "Pass"
        case .warn: return "Warning"
        case .fail: return "Failure"
        case .skipped: return "Skipped"
        }
    }
}

/// The content column for the Diagnostics section: pick a target (System or a
/// bottle), run the checks, and list each result with a glyph and colour.
struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            targetBar
            Divider()
            banner
            Divider()
            checkList
        }
        .navigationTitle("Diagnostics")
        .frame(minWidth: 300)
        .toolbar { toolbarContent }
        .onAppear {
            model.refreshBottles()
            model.runDiagnostics()
        }
    }

    // MARK: Target

    private var targetBar: some View {
        HStack {
            Picker("Target", selection: $model.diagnosticBottle) {
                Text("System").tag(String?.none)
                ForEach(model.bottles) { bottle in
                    Text(bottle.name).tag(String?.some(bottle.name))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: model.diagnosticBottle) { _ in
                model.selectedDiagnosticCheckID = nil
                model.runDiagnostics()
            }
            Spacer()
            if model.isRunningDiagnostics {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Summary banner

    @ViewBuilder
    private var banner: some View {
        if let report = model.diagnosticReport {
            let failures = report.checks.filter { $0.status == .fail }.count
            let warnings = report.checks.filter { $0.status == .warn }.count
            HStack(spacing: 8) {
                Image(systemName: bannerIcon(failures: failures, warnings: warnings))
                    .foregroundStyle(bannerColor(failures: failures, warnings: warnings))
                VStack(alignment: .leading, spacing: 1) {
                    Text(bannerTitle(failures: failures, warnings: warnings))
                        .font(.callout)
                        .bold()
                    Text("\(report.checks.count) checks · \(failures) failures · \(warnings) warnings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bannerColor(failures: failures, warnings: warnings).opacity(0.08))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "stethoscope")
                    .foregroundStyle(.secondary)
                Text(model.isRunningDiagnostics ? "Running checks…" : "No results yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func bannerTitle(failures: Int, warnings: Int) -> String {
        if failures > 0 { return "\(failures) problem\(failures == 1 ? "" : "s") found" }
        if warnings > 0 { return "\(warnings) warning\(warnings == 1 ? "" : "s")" }
        return "Everything looks good"
    }

    private func bannerIcon(failures: Int, warnings: Int) -> String {
        if failures > 0 { return "xmark.octagon.fill" }
        if warnings > 0 { return "exclamationmark.triangle.fill" }
        return "checkmark.seal.fill"
    }

    private func bannerColor(failures: Int, warnings: Int) -> Color {
        if failures > 0 { return .red }
        if warnings > 0 { return .orange }
        return .green
    }

    // MARK: Checks

    @ViewBuilder
    private var checkList: some View {
        if let report = model.diagnosticReport, !report.checks.isEmpty {
            List(selection: $model.selectedDiagnosticCheckID) {
                Section("Checks") {
                    ForEach(report.checks, id: \.id) { check in
                        DiagnosticCheckRow(check: check)
                            .tag(Optional(check.id))
                    }
                }
            }
        } else if model.isRunningDiagnostics {
            EmptyStateView(
                icon: "stethoscope",
                title: "Running Diagnostics",
                message: "Checking your Mac, the Wine runtime and the selected bottle…"
            )
        } else {
            EmptyStateView(
                icon: "stethoscope",
                title: "No Results",
                message: "Run the diagnostics to check your Mac, the Wine runtime and the selected bottle."
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.runDiagnostics()
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .disabled(model.isRunningDiagnostics)
            .help("Run the diagnostics for the selected target")
        }
    }
}

/// A single diagnostic check row: status glyph + colour, title, and detail.
struct DiagnosticCheckRow: View {
    let check: DiagnosticCheck

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: check.status.guiSymbol)
                .foregroundStyle(check.status.guiColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.callout)
                    .lineLimit(2)
                if let detail = check.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// The detail pane for the Diagnostics section: the selected check's full
/// detail, or a report summary when nothing is selected.
struct DiagnosticsDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let check = model.selectedDiagnosticCheck {
                checkDetail(check)
            } else if let report = model.diagnosticReport {
                reportSummary(report)
            } else {
                EmptyStateView(
                    icon: "stethoscope",
                    title: "No Diagnostics",
                    message: "Pick a target and run the diagnostics to see detailed results here."
                )
            }
        }
    }

    @ViewBuilder
    private func checkDetail(_ check: DiagnosticCheck) -> some View {
        Form {
            Section("Result") {
                HStack(spacing: 8) {
                    Image(systemName: check.status.guiSymbol)
                        .font(.title2)
                        .foregroundStyle(check.status.guiColor)
                    Text(check.status.guiLabel)
                        .font(.headline)
                        .foregroundStyle(check.status.guiColor)
                }
            }
            Section("Check") {
                LabeledContent("Title", value: check.title)
                LabeledContent("Identifier", value: check.id)
            }
            if let detail = check.detail, !detail.isEmpty {
                Section("Detail") {
                    Text(detail)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(check.title)
    }

    @ViewBuilder
    private func reportSummary(_ report: DiagnosticReport) -> some View {
        Form {
            Section("Target") {
                LabeledContent("Bottle", value: report.bottle ?? "System")
                LabeledContent("Checks", value: "\(report.checks.count)")
                LabeledContent("Warnings", value: "\(report.checks.filter { $0.status == .warn }.count)")
                LabeledContent("Failures", value: "\(report.checks.filter { $0.status == .fail }.count)")
            }
            Section("Checks") {
                ForEach(report.checks, id: \.id) { check in
                    HStack(spacing: 8) {
                        Image(systemName: check.status.guiSymbol)
                            .foregroundStyle(check.status.guiColor)
                            .frame(width: 18)
                        Text(check.title)
                            .lineLimit(1)
                        Spacer()
                        Text(check.status.guiLabel)
                            .font(.caption)
                            .foregroundStyle(check.status.guiColor)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Diagnostics")
    }
}
