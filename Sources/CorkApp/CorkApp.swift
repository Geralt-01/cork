import SwiftUI
import CorkKit
import CorkEngine

@main
struct CorkApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Root navigation shell. The GUI track expands this into the full CrossOver-like
/// experience (bottles, app catalog, install wizard, settings).
struct RootView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Section("Cork") {
                    Label("Bottles", systemImage: "shippingbox")
                    Label("Applications", systemImage: "square.grid.2x2")
                }
            }
            .navigationTitle("Cork")
            .frame(minWidth: 200)
        } detail: {
            VStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("Cork")
                    .font(.title2)
                Text("Native macOS front-end for Cork — under construction.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
