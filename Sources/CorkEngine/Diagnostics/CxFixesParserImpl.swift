import Foundation

/// SAX parser for CrossOver's `cxfixes.xml`.
///
/// Only the `<fixes>` section is interpreted. Each `<fix>` contributes one
/// entry keyed by its `id` (falling back to `title`); the value list holds the
/// fix's `description` (falling back to `title`). The `<distributions>` and
/// `<cxproducts>` sections are scanned but ignored — they configure host
/// package installation, which is irrelevant on macOS.
///
/// The parser is defensive by design: an unreadable file, non-`cxfixes` root or
/// malformed XML yields an empty map rather than an error.
enum CxFixesSAX {
    static func parse(fileURL: URL) -> [String: [String]] {
        guard let stream = InputStream(url: fileURL) else { return [:] }
        let delegate = Delegate()
        let parser = XMLParser(stream: stream)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.sawRoot else { return [:] }
        return delegate.fixes
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private(set) var fixes: [String: [String]] = [:]
        private(set) var sawRoot = false

        private var insideFix = false
        private var insideDescription = false
        private var currentID: String?
        private var currentTitle: String?
        private var attributeDescription: String?
        private var childDescription = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String]
        ) {
            switch elementName {
            case "cxfixes":
                sawRoot = true
            case "fix":
                insideFix = true
                currentID = attributeDict["id"]
                currentTitle = attributeDict["title"]
                attributeDescription = attributeDict["description"]
                childDescription = ""
            case "description":
                if insideFix {
                    insideDescription = true
                    childDescription = ""
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if insideDescription { childDescription += string }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if insideDescription, let decoded = String(data: CDATABlock, encoding: .utf8) {
                childDescription += decoded
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch elementName {
            case "description":
                insideDescription = false
            case "fix":
                store()
                insideFix = false
                currentID = nil
                currentTitle = nil
                attributeDescription = nil
                childDescription = ""
            default:
                break
            }
        }

        private func store() {
            let id = trimmed(currentID)
            let title = trimmed(currentTitle)
            guard let key = id ?? title, !key.isEmpty else { return }

            // Prefer a real description, then the title, then the id, so a
            // terse fix (e.g. `<fix id="x11notworking.amd64">`) is still
            // counted rather than silently dropped.
            let description = firstNonEmpty(
                trimmed(attributeDescription),
                trimmed(childDescription),
                title,
                key
            )
            guard let description else { return }

            if var existing = fixes[key] {
                if !existing.contains(description) { existing.append(description) }
                fixes[key] = existing
            } else {
                fixes[key] = [description]
            }
        }

        private func trimmed(_ value: String?) -> String? {
            guard let value else { return nil }
            let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        }

        private func firstNonEmpty(_ candidates: String?...) -> String? {
            candidates.compactMap { $0 }.first
        }
    }
}
