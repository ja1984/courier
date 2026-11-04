import AppKit
import CourierCore
import UniformTypeIdentifiers

/// Export and import of collection files, using the standard save and open panels.
extension AppStore {
    /// Exports the given collections (all when nil). The save panel asks whether to include secret values.
    func exportCollections(_ ids: [UUID]? = nil) {
        let collections = ids.map { ids in library.collections.filter { ids.contains($0.id) } } ?? library.collections
        guard !collections.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = collections.count == 1 ? "Export “\(collections[0].name)”" : "Export Collections"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let baseName = collections.count == 1 ? collections[0].name : "Courier Collections"
        panel.nameFieldStringValue = "\(baseName.replacingOccurrences(of: "/", with: "-")).courier.json"

        let includeSecrets = NSButton(checkboxWithTitle: "Include secret values", target: nil, action: nil)
        includeSecrets.state = .off
        let explanation = NSTextField(wrappingLabelWithString:
            "Tokens, API keys, cookies and passwords in headers and query parameters. When unchecked they're exported empty, so the file is safe to share.")
        explanation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        explanation.textColor = .secondaryLabelColor
        explanation.preferredMaxLayoutWidth = 360
        let accessory = NSStackView(views: [includeSecrets, explanation])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 4
        accessory.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        panel.accessoryView = accessory

        present(panel) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try CollectionTransfer.export(collections, includeSecrets: includeSecrets.state == .on)
                try data.write(to: url, options: .atomic)
            } catch {
                self?.alert = AppAlert(title: "Couldn't export", message: error.localizedDescription)
            }
        }
    }

    /// Imports Courier or Postman collection files as new collections.
    func importCollections() {
        let panel = NSOpenPanel()
        panel.title = "Import Collections"
        panel.prompt = "Import"
        panel.message = "Choose Courier or Postman (v2.1) collection files."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        present(panel) { [weak self] response in
            guard response == .OK else { return }
            self?.importCollections(from: panel.urls)
        }
    }

    func importCollections(from urls: [URL]) {
        var imported: [RequestCollection] = []
        var notes: [String] = []
        var failures: [String] = []
        for url in urls {
            do {
                let result = try CollectionTransfer.importFile(try Data(contentsOf: url))
                imported += result.collections
                notes += result.notes
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !imported.isEmpty {
            library.add(imported)
            persistence.saveCollections(library)
            // Show what was just imported.
            UserDefaults.standard.set("collections", forKey: "sidebarMode")
        }

        let requestCount = imported.reduce(0) { $0 + $1.requests.count }
        var lines: [String] = []
        if !imported.isEmpty {
            lines.append("\(imported.count == 1 ? "1 collection" : "\(imported.count) collections") with \(requestCount == 1 ? "1 request" : "\(requestCount) requests").")
        }
        lines += Array(Set(notes)).sorted()
        lines += failures
        alert = AppAlert(
            title: imported.isEmpty ? "Nothing was imported" : "Imported",
            message: lines.joined(separator: "\n\n")
        )
    }

    private func present(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }
}
