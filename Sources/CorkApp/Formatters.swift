import SwiftUI

/// Wraps a value that we know is safe to move across concurrency domains but
/// that CorkKit/CorkEngine do not (yet) declare `Sendable`.
///
/// The GUI owns these values exclusively for the duration of a background task,
/// so the unchecked conformance is sound in practice.
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// A filled-in star rating, e.g. `★★★☆☆`. Returns a dash when unknown.
func stars(for rating: Int?) -> String {
    guard let rating else { return "—" }
    let clamped = max(0, min(5, rating))
    return String(repeating: "★", count: clamped)
        + String(repeating: "☆", count: 5 - clamped)
}

/// Colour used for a CrossTie medal label.
func medalColor(_ medal: String?) -> Color {
    switch medal?.lowercased() {
    case "gold": return .yellow
    case "silver": return .gray
    case "bronze": return .orange
    case "ungold", "none": return .secondary
    default: return .secondary
    }
}

/// A friendly, non-empty representation of an optional string field.
func display(_ value: String?, placeholder: String = "—") -> String {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return placeholder
    }
    return value
}

/// Centered placeholder used whenever a pane has nothing to show.
struct EmptyStateView<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    let actions: Actions

    init(icon: String, title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .bold()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            actions
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}
