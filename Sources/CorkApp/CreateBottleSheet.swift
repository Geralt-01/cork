import SwiftUI
import CorkKit

/// Sheet for creating a bottle. Shows live progress from `BottleCreateEvent`.
struct CreateBottleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var backend: GraphicsBackend = .dxmt
    @State private var windows: WindowsVersion = .win10

    private var isValid: Bool {
        (try? Bottle.validateName(name.trimmingCharacters(in: .whitespacesAndNewlines))) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Bottle")
                .font(.title2)
                .bold()

            Form {
                LabeledContent("Name") {
                    TextField("My Bottle", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                        .disabled(model.isCreating)
                }
                LabeledContent("Graphics backend") {
                    Picker("", selection: $backend) {
                        ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 220)
                    .disabled(model.isCreating)
                }
                LabeledContent("Windows version") {
                    Picker("", selection: $windows) {
                        ForEach(WindowsVersion.allCases, id: \.self) { version in
                            Text(version.displayName).tag(version)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 220)
                    .disabled(model.isCreating)
                }
            }
            .formStyle(.grouped)
            .frame(height: 210)

            Text("Backend: \(backend.summary)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.createLog.isEmpty || model.isCreating {
                progressView
            }

            if let error = model.createError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if !model.isWineReady {
                    Text("Install the Wine runtime first.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isCreating)
                Button("Create") {
                    model.createBottle(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        settings: BottleSettings(windowsVersion: windows, backend: backend)
                    )
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || model.isCreating || !model.isWineReady)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onChange(of: model.createdBottleName) { newValue in
            if newValue != nil { dismiss() }
        }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if model.isCreating {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.isCreating ? "Working…" : "Done")
                    .font(.callout)
                    .bold()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.createLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 80)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
