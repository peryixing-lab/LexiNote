import Foundation

// MARK: - Markdown file + frontmatter codec

enum NoteCodec {
    static func encode(_ note: Note) -> String {
        var lines: [String] = ["---"]
        lines.append("id: \(yaml(note.id))")
        lines.append("title: \(yaml(note.title))")
        lines.append("notebook: \(yaml(note.notebook))")
        lines.append("type: \(note.type.rawValue)")
        lines.append("level: \(note.level.rawValue)")
        lines.append("pinned: \(note.pinned ? "true" : "false")")
        lines.append("favorite: \(note.favorite ? "true" : "false")")
        lines.append("tags: [\(note.tags.map { yaml($0) }.joined(separator: ", "))]")
        lines.append("created: \(LexiDate.iso(note.createdAt))")
        lines.append("updated: \(LexiDate.iso(note.updatedAt))")
        if let trashed = note.trashedAt { lines.append("trashed: \(LexiDate.iso(trashed))") }
        if !note.properties.isEmpty {
            lines.append("properties:")
            for property in note.properties {
                lines.append("  - key: \(yaml(property.key))")
                lines.append("    value: \(yaml(property.value))")
            }
        }
        lines.append("---")
        lines.append("")
        lines.append(stripFrontmatter(note.content))
        return lines.joined(separator: "\n")
    }

    private static func stripFrontmatter(_ raw: String) -> String {
        let body = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard body.hasPrefix("---\n") else { return raw }
        let lines = body.components(separatedBy: "\n")
        for idx in 1..<lines.count {
            let t = lines[idx].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." {
                return lines.dropFirst(idx + 1).joined(separator: "\n")
                    .replacingOccurrences(of: "^\\n+", with: "", options: .regularExpression)
            }
        }
        return raw
    }

    static func decode(text: String, relativePath: String, vaultID: String,
                       fallbackNotebook: String, fileDate: Date) -> Note? {
        var body = text.replacingOccurrences(of: "\r\n", with: "\n")
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        var meta: [String: String] = [:]
        var properties: [NoteProperty] = []
        var bodyText = body

        if body.hasPrefix("---\n") || body == "---" {
            let lines = body.components(separatedBy: "\n")
            var closing: Int?
            var index = 1
            while index < lines.count {
                if lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                    closing = index
                    break
                }
                index += 1
            }
            if let closing {
                var currentKey: String?
                for lineIndex in 1..<closing {
                    let line = lines[lineIndex]
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                    if line.hasPrefix("  - key: ") {
                        currentKey = unquote(String(line.dropFirst("  - key: ".count)))
                        continue
                    }
                    if line.hasPrefix("    value: "), let key = currentKey {
                        properties.append(NoteProperty(key: key, value: unquote(String(line.dropFirst("    value: ".count)))))
                        currentKey = nil
                        continue
                    }
                    if let colon = trimmed.firstIndex(of: ":") {
                        let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                        let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        if key == "properties" { continue }
                        let systemKeys: Set<String> = ["id", "title", "notebook", "type", "level", "pinned", "favorite", "tags", "tag", "created", "updated", "trashed"]
                        if systemKeys.contains(key) {
                            meta[key] = value
                        } else {
                            properties.append(NoteProperty(key: String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces), value: unquote(value)))
                        }
                    }
                }
                bodyText = lines.dropFirst(closing + 1).joined(separator: "\n")
            }
        }

        while bodyText.hasPrefix("\n") { bodyText.removeFirst() }

        let id = meta["id"].map(unquote).flatMap { $0.isEmpty ? nil : $0 } ?? "note-\(UUID().uuidString.lowercased())"
        let notebook = meta["notebook"].map(unquote) ?? fallbackNotebook
        let title = meta["title"].map(unquote) ?? ""
        let type = NoteKind(rawValue: unquote(meta["type"] ?? "")) ?? .markdown
        let level = EditorLevel(rawValue: unquote(meta["level"] ?? "")) ?? (type == .quick ? .simple : .study)
        let tags = (meta["tags"] ?? meta["tag"]).map(parseList) ?? []
        let createdAt = meta["created"].flatMap(parseFlexDate) ?? fileDate
        let updatedAt = meta["updated"].flatMap(parseFlexDate) ?? fileDate
        let trashedAt = meta["trashed"].flatMap(parseFlexDate)
        let note = Note(id: id, vaultID: vaultID, notebook: notebook, type: type, level: level,
                        title: title, content: bodyText, tags: tags, properties: properties,
                        pinned: meta["pinned"]?.lowercased() == "true",
                        favorite: meta["favorite"]?.lowercased() == "true",
                        createdAt: createdAt, updatedAt: updatedAt, trashedAt: trashedAt,
                        path: relativePath)
        return note
    }

    private static func yaml(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    static func unquote(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text.removeFirst()
            text.removeLast()
            text = text.replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return text
    }

    private static func parseList(_ raw: String) -> [String] {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("[") { value.removeFirst() }
        if value.hasSuffix("]") { value.removeLast() }
        guard let regex = try? NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"|[^,]+") else { return [] }
        let ns = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let piece = ns.substring(with: match.range).trimmingCharacters(in: .whitespaces)
            let clean = unquote(piece)
            return clean.isEmpty ? nil : clean
        }
    }

    private static func parseFlexDate(_ raw: String) -> Date? {
        let clean = unquote(raw)
        if let d = LexiDate.parse(clean) { return d }
        if let num = Double(clean), num > 0 {
            return Date(timeIntervalSince1970: num > 1e11 ? num / 1000.0 : num)
        }
        return nil
    }

    private static func stableID(_ relativePath: String) -> String {
        var hash: UInt64 = 5381
        for byte in relativePath.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let slug = relativePath
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "note-\(slug)-\(String(hash % 1000000, radix: 16))"
    }
}
