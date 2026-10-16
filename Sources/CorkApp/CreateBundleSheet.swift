import SwiftUI
import AppKit

/// Sheet that turns a selected Windows executable into a native macOS `.app`
/// bundle via `AppBundler`. Defaults the output to `~/Applications` and lets the
/// user attach an optional icon chosen with an open panel.
struct CreateBundleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create macOS App")
                .font(.title2)
                .bold()

            Form {
                Section("Program") {
                    LabeledContent("Executable") {
                        Text(model.bundleExecutableURL?.lastPathComponent ?? "—")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    LabeledContent("Bottle", value: model.bundleBottleName)
                }

                Section("Bundle") {
                    LabeledContent("App name") {
                        TextField("App name", text: $model.bundleName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 240)
                            .disabled(model.isBundling)
                    }
                    LabeledContent("Arguments") {
                        TextField("optional arguments", text: $model.bundleArguments)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 240)
                            .disabled(model.isBundling)
                    }
                    LabeledContent("Output folder") {
                        HStack(spacing: 6) {
                            Text(model.bundleOutputDirectory.path)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…") { model.chooseBundleOutputDirectory() }
                                .disabled(model.isBundling)
                        }
                    }
                    LabeledContent("Icon") {
                        HStack(spacing: 6) {
                            Text(model.bundleIconPath?.lastPathComponent ?? "Default")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…") { model.chooseBundleIcon() }
                                .disabled(model.isBundling)
                            if model.bundleIconPath != nil {
                                Button("Clear") { model.bundleIconPath = nil }
                                    .disabled(model.isBundling)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let url = model.bundledAppURL {
                resultView(url)
            }

            if let error = model.bundleError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(20)
        .frame(width: 560)
    }

    private func resultView(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Created \(url.lastPathComponent)")
                    .font(.callout)
                    .bold()
                Text(url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                model.revealInFinder(url)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            if model.isBundling {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(model.bundledAppURL != nil ? .defaultAction : .cancelAction)
            Button("Create") { model.createBundle() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.bundleIsValid || model.isBundling)
        }
    }
}
