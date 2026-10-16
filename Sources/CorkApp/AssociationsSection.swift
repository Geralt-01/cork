import SwiftUI
import CorkKit
import CorkEngine

/// A `Form` section, embedded in the bottle detail/settings pane, listing and
/// editing a bottle's file-type associations (extension → Windows program).
struct AssociationsSection: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    var body: some View {
        Section("File Associations") {
            if model.associations.isEmpty {
                Text("No file associations configured.")
                    .foregroundStyle(.secondary)
                Text("Add one to open a Mac file type with a Windows program in this bottle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.associations, id: \.fileExtension) { entry in
                    AssociationRow(entry: entry) {
                        model.removeAssociation(fileExtension: entry.fileExtension)
                    }
                }
            }

            HStack {
                Button {
                    model.requestAddAssociation(bottleName: bottle.name)
                } label: {
                    Label("Add Association…", systemImage: "plus")
                }

                if !model.associations.isEmpty {
                    Button {
                        model.toggleAssociationsRegistry()
                    } label: {
                        Label(
                            model.showAssociationsRegistry ? "Hide Registry Commands" : "Show Registry Commands",
                            systemImage: "list.bullet.rectangle"
                        )
                    }
                }

                Spacer()
            }

            if model.showAssociationsRegistry {
                if model.associationsRegistryLines.isEmpty {
                    Text("No registry commands.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.associationsRegistryLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .onAppear { model.ensureAssociationsLoaded(for: bottle.name) }
        .onChange(of: bottle.name) { name in
            model.loadAssociations(bottleName: name)
        }
    }
}

/// A single association row with a remove action.
private struct AssociationRow: View {
    let entry: AssociationEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.badge.arrow.up")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.fileExtension)
                        .font(.system(.callout, design: .monospaced))
                        .bold()
                    if let friendly = entry.friendlyName, !friendly.isEmpty {
                        Text(friendly)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.executable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(entry.progID)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove this association")
        }
        .padding(.vertical, 2)
    }
}

/// Sheet for adding a single file association to a bottle.
struct AddAssociationSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add File Association")
                    .font(.title2)
                    .bold()
                Text(model.associationsBottleName.map { "Bottle: \($0)" } ?? "No bottle selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("Association") {
                    LabeledContent("Extension") {
                        TextField(".psd", text: $model.associationFormExtension)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)
                    }
                    LabeledContent("Windows program") {
                        TextField(#"C:\Program Files\App\app.exe"#, text: $model.associationFormExecutable)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)
                    }
                    LabeledContent("Friendly name") {
                        TextField("Optional", text: $model.associationFormFriendlyName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)
                    }
                    LabeledContent("ProgID") {
                        TextField("Optional — generated if empty", text: $model.associationFormProgID)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180)
                    }
                }
            }
            .formStyle(.grouped)

            Text("The program path is a Windows path inside the bottle, e.g. C:\\Program Files\\App\\app.exe. Windows treats extensions case-insensitively.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { model.addAssociation() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.associationFormIsValid)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}
