import Foundation

public struct GraphicsInstaller {
    public let runtime: RuntimeManager

    public init(runtime: RuntimeManager) {
        self.runtime = runtime
    }

    public func setBackend(_ backend: GraphicsBackend, on bottle: inout Bottle) throws {
        // Install the new backend first, then drop only the files the previous
        // backend owned. If installation fails midway the bottle keeps its old
        // (working) runtime instead of ending up with no graphics DLLs.
        let previousFiles = bottle.metadata.graphicsFiles
        let files: [String]
        switch backend {
        case .wined3d:
            files = []
        case .dxvk:
            files = try installDXVK(into: &bottle)
        case .dxmt:
            files = try installDXMT(into: &bottle)
        }
        removeInstalledFiles(previousFiles, keeping: Set(files), from: &bottle)
        bottle.metadata.graphicsFiles = files
        bottle.metadata.settings.backend = backend
        try bottle.save()
    }

    public func ensureBackendInstalled(on bottle: inout Bottle) throws {
        try setBackend(bottle.settings.backend, on: &bottle)
    }

    private func componentDirectory(_ id: String) throws -> URL {
        guard let component = runtime.manifest.component(id: id) else {
            throw CorkError.componentUnknown(id: id)
        }
        guard runtime.store.isInstalled(component) else {
            throw CorkError.componentNotInstalled(id: id, version: component.version)
        }
        return runtime.componentDirectory(component)
    }

    private func removeInstalledFiles(_ files: [String], keeping keep: Set<String>, from bottle: inout Bottle) {
        let fm = FileManager.default
        for relative in files where !keep.contains(relative) {
            let url = bottle.url.appendingPathComponent(relative)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func installDXVK(into bottle: inout Bottle) throws -> [String] {
        let source = try componentDirectory("dxvk")
        var installed: [String] = []
        installed += try copyDLLs(from: source.appendingPathComponent("x64"), to: bottle.system32Directory, in: bottle)
        installed += try copyDLLs(from: source.appendingPathComponent("x32"), to: bottle.syswow64Directory, in: bottle)
        return installed
    }

    private func installDXMT(into bottle: inout Bottle) throws -> [String] {
        let source = try componentDirectory("dxmt")
        var installed: [String] = []

        for architecture in ["x86_64-windows", "i386-windows", "x86_64-unix"] {
            let from = source.appendingPathComponent(architecture)
            let to = bottle.graphicsDirectory.appendingPathComponent(architecture)
            installed += try copyTree(from: from, to: to, in: bottle)
        }

        let winemetal64 = source.appendingPathComponent("x86_64-windows/winemetal.dll")
        if FileManager.default.fileExists(atPath: winemetal64.path) {
            installed.append(try copyFile(winemetal64, to: bottle.system32Directory.appendingPathComponent("winemetal.dll"), in: bottle))
        }
        let winemetal32 = source.appendingPathComponent("i386-windows/winemetal.dll")
        if FileManager.default.fileExists(atPath: winemetal32.path) {
            installed.append(try copyFile(winemetal32, to: bottle.syswow64Directory.appendingPathComponent("winemetal.dll"), in: bottle))
        }

        return installed
    }

    private func copyDLLs(from source: URL, to destination: URL, in bottle: Bottle) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return [] }
        let entries = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        var installed: [String] = []
        for entry in entries where entry.pathExtension.lowercased() == "dll" {
            installed.append(try copyFile(entry, to: destination.appendingPathComponent(entry.lastPathComponent), in: bottle))
        }
        return installed
    }

    private func copyTree(from source: URL, to destination: URL, in bottle: Bottle) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return [] }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let entries = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        var installed: [String] = []
        for entry in entries {
            let target = destination.appendingPathComponent(entry.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: entry, to: target)
            installed.append(relativePath(of: target, in: bottle))
        }
        return installed
    }

    private func copyFile(_ source: URL, to destination: URL, in bottle: Bottle) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
        return relativePath(of: destination, in: bottle)
    }

    private func relativePath(of url: URL, in bottle: Bottle) -> String {
        let base = bottle.url.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        return url.lastPathComponent
    }
}
