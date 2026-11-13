import SwiftUI
import AppKit

// MARK: - Editor controller


final class EditorController: ObservableObject {
    @MainActor static weak var active: EditorController?
    weak var textView: NSTextView?
    var onChange: ((String) -> Void)?

    @MainActor
    func bindActive() {
        EditorController.active = self
    }

    func focus() {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
    }

    var isFocused: Bool {
        guard let textView else { return false }
        return textView.window?.firstResponder === textView
    }

    func selectedRange() -> NSRange {
        textView?.selectedRange() ?? NSRange(location: 0, length: 0)
    }

    func selectedText() -> String {
        guard let textView else { return "" }
        let range = textView.selectedRange()
        guard range.length > 0, let swiftRange = Range(range, in: textView.string) else { return "" }
        return String(textView.string[swiftRange])
    }

    func setSelection(_ range: NSRange) {
        guard let textView else { return }
        let safeLocation = min(range.location, (textView.string as NSString).length)
        let safeLength = min(range.length, (textView.string as NSString).length - safeLocation)
        textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
        textView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
    }

    func replace(range: NSRange, with text: String) {
        guard let textView else { return }
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        let newLocation = range.location + (text as NSString).length
        textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        textView.scrollRangeToVisible(NSRange(location: newLocation, length: 0))
        onChange?(textView.string)
    }

    func insert(_ text: String) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()
        replace(range: range, with: text)
    }

    func wrap(prefix: String, suffix: String, placeholder: String) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()
        let ns = textView.string as NSString
        let selected = range.length > 0 ? ns.substring(with: range) : placeholder
        // Toggle off when the selection is already wrapped.
        if range.length > 0,
           range.location >= (prefix as NSString).length,
           NSMaxRange(range) + (suffix as NSString).length <= ns.length {
            let before = ns.substring(with: NSRange(location: range.location - (prefix as NSString).length,
                                                    length: (prefix as NSString).length))
            let after = ns.substring(with: NSRange(location: NSMaxRange(range), length: (suffix as NSString).length))
            if before == prefix && after == suffix {
                let full = NSRange(location: range.location - (prefix as NSString).length,
                                   length: range.length + (prefix as NSString).length + (suffix as NSString).length)
                replace(range: full, with: selected)
                textView.setSelectedRange(NSRange(location: range.location - (prefix as NSString).length,
                                                  length: (selected as NSString).length))
                return
            }
        }
        let replacement = prefix + selected + suffix
        replace(range: range, with: replacement)
        if range.length == 0 {
            textView.setSelectedRange(NSRange(location: range.location + (prefix as NSString).length,
                                              length: (selected as NSString).length))
        }
    }

    func apply(_ command: EditorCommand) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let selection = textView.selectedRange()
        let ns = textView.string as NSString

        func lineRange(at location: Int) -> NSRange {
            let safe = min(max(0, location), ns.length)
            return ns.lineRange(for: NSRange(location: safe, length: 0))
        }

        func transformLine(_ transform: (String) -> String) {
            let range = lineRange(at: selection.location)
            let current = ns.substring(with: range)
            let replacement = transform(current)
            replace(range: range, with: replacement)
        }

        switch command {
        case .bold:
            wrap(prefix: "**", suffix: "**", placeholder: "粗体内容")
        case .italic:
            wrap(prefix: "*", suffix: "*", placeholder: "强调内容")
        case .strike:
            wrap(prefix: "~~", suffix: "~~", placeholder: "待修订内容")
        case .highlight:
            wrap(prefix: "==", suffix: "==", placeholder: "重点内容")
        case .h1:
            transformLine { line in
                let body = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let stripped = body.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
                return "# \(stripped)\n"
            }
        case .h2:
            transformLine { line in
                let body = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let stripped = body.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
                return "## \(stripped)\n"
            }
        case .h3:
            transformLine { line in
                let body = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let stripped = body.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
                return "### \(stripped)\n"
            }
        case .h4:
            transformLine { line in
                let body = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let stripped = body.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
                return "#### \(stripped)\n"
            }
        case .h5:
            transformLine { line in
                let body = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let stripped = body.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
                return "##### \(stripped)\n"
            }
        case .h6:
            transformLine { line in
                let body = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let stripped = body.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
                return "###### \(stripped)\n"
            }
        case .headingClear:
            transformLine { line in
                let body = line.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
                return body
            }
        case .bullet:
            transformLine { line in
                let trimmed = line.replacingOccurrences(of: "\n", with: "")
                if trimmed.hasPrefix("- ") { return trimmed + "\n" }
                return "- \(trimmed)\n"
            }
        case .ordered:
            transformLine { line in
                let trimmed = line.replacingOccurrences(of: "\n", with: "")
                if trimmed.hasPrefix("1. ") { return trimmed + "\n" }
                return "1. \(trimmed)\n"
            }
        case .indent:
            transformLine { "  " + $0 }
        case .outdent:
            transformLine { $0.replacingOccurrences(of: "^(  |\\t)", with: "", options: .regularExpression) }
        case .quote:
            transformLine { line in
                let trimmed = line.replacingOccurrences(of: "\n", with: "")
                return trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) + "\n" : "> \(trimmed)\n"
            }
        case .todo:
            insert("- [ ] 待完成事项")
        case .table:
            insert("\n| 项目 | 内容 |\n| --- | --- |\n|  |  |\n")
        case .code:
            let selected = selection.length > 0 ? ns.substring(with: selection) : ""
            insert("\n```\n\(selected)\n```\n")
        case .inlineCode:
            wrap(prefix: "`", suffix: "`", placeholder: "code")
        case .formula:
            let selected = selection.length > 0 ? ns.substring(with: selection) : "f(n) = O(n \\log n)"
            insert("\n$$\n\(selected)\n$$\n")
        case .inlineMath:
            wrap(prefix: "$", suffix: "$", placeholder: "x^2")
        case .callout:
            insert("\n> [!NOTE] 知识要点\n> 在此记录要点\n")
        case .link:
            let selected = selection.length > 0 ? ns.substring(with: selection) : "笔记标题"
            insert("[[\(selected)]]")
        case .embed:
            let selected = selection.length > 0 ? ns.substring(with: selection) : "笔记标题"
            insert("![[\(selected)]]")
        case .footnote:
            let selected = selection.length > 0 ? ns.substring(with: selection) : "1"
            insert("[^\(selected)]")
        case .comment:
            wrap(prefix: "%%", suffix: "%%", placeholder: "注释")
        case .clearFormat:
            if selection.length > 0 {
                var selected = ns.substring(with: selection)
                selected = selected
                    .replacingOccurrences(of: "\\*\\*(.*?)\\*\\*", with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: "~~(.*?)~~", with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: "==(.*?)==", with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: "`(.*?)`", with: "$1", options: .regularExpression)
                replace(range: selection, with: selected)
            }
        case .lineUp:
            let current = lineRange(at: selection.location)
            guard current.location > 0 else { return }
            let prev = lineRange(at: current.location - 1)
            let prevStr = ns.substring(with: prev)
            let currStr = ns.substring(with: current)
            let needNL = !currStr.hasSuffix("\n") && prevStr.hasSuffix("\n")
            let swapped = (needNL ? currStr + "\n" : currStr) + (needNL ? String(prevStr.dropLast()) : prevStr)
            let combined = NSRange(location: prev.location, length: prev.length + current.length)
            replace(range: combined, with: swapped)
            setSelection(NSRange(location: prev.location, length: 0))
        case .lineDown:
            let current = lineRange(at: selection.location)
            let nextStart = NSMaxRange(current)
            guard nextStart < ns.length else { return }
            let next = lineRange(at: nextStart)
            let currStr = ns.substring(with: current)
            let nextStr = ns.substring(with: next)
            let needNL = !nextStr.hasSuffix("\n") && currStr.hasSuffix("\n")
            let swapped = (needNL ? nextStr + "\n" : nextStr) + (needNL ? String(currStr.dropLast()) : currStr)
            let combined = NSRange(location: current.location, length: current.length + next.length)
            replace(range: combined, with: swapped)
            setSelection(NSRange(location: current.location + (nextStr as NSString).length, length: 0))
        case .deleteParagraph:
            let current = lineRange(at: selection.location)
            replace(range: current, with: "")
        case .date:
            insert(LexiDate.dayKey())
        case .time:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            insert(formatter.string(from: Date()))
        case .reading, .source, .split, .fold, .unfold, .find, .focus:
            break
        }
    }

    @discardableResult
    func findNext(_ query: String, fromSelection: Bool = true) -> Bool {
        guard let textView, !query.isEmpty else { return false }
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let start = fromSelection ? min(NSMaxRange(selection), ns.length) : 0
        var found = ns.range(of: query, options: [.caseInsensitive], range: NSRange(location: start, length: ns.length - start))
        if found.location == NSNotFound && start > 0 {
            found = ns.range(of: query, options: [.caseInsensitive], range: NSRange(location: 0, length: ns.length))
        }
        guard found.location != NSNotFound else { return false }
        textView.setSelectedRange(found)
        textView.scrollRangeToVisible(found)
        textView.window?.makeFirstResponder(textView)
        return true
    }

    func selectLine(_ line: Int) {
        guard let textView else { return }
        let ns = textView.string as NSString
        var currentLine = 0
        var location = 0
        while location < ns.length && currentLine < line {
            let range = ns.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(range)
            currentLine += 1
        }
        let target = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        textView.setSelectedRange(NSRange(location: target.location, length: 0))
        textView.scrollRangeToVisible(target)
        textView.window?.makeFirstResponder(textView)
    }
}

// MARK: - SwiftUI wrapper

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    let palette: ThemePalette
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let design: EditorFontDesign
    let spellCheck: Bool
    let controller: EditorController
    let onTextChange: (String) -> Void
    var onSelectionChange: ((NSRange) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false

        let textView = NSTextView()
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = spellCheck
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.typingAttributes = baseAttributes()
        textView.delegate = context.coordinator
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.parent = self
        controller.textView = textView
        controller.onChange = onTextChange
        EditorController.active = controller
        context.coordinator.applyStyling()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        controller.textView = textView
        controller.onChange = onTextChange
        EditorController.active = controller
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let ns = textView.string as NSString
            let safe = min(selection.location, ns.length)
            textView.setSelectedRange(NSRange(location: safe, length: 0))
        }
        textView.isContinuousSpellCheckingEnabled = spellCheck
        textView.typingAttributes = baseAttributes()
        textView.insertionPointColor = NSColor(palette.brand)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(palette.brand).withAlphaComponent(0.22),
            .foregroundColor: NSColor(palette.textPrimary)
        ]
        context.coordinator.applyStyling()
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        let font = editorFont(size: fontSize)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = max(3, fontSize * (lineHeight - 1.25))
        style.paragraphSpacing = fontSize * 0.42
        style.lineBreakMode = .byWordWrapping
        return [
            .font: font,
            .foregroundColor: NSColor(palette.textPrimary),
            .paragraphStyle: style,
            .kern: 0.1
        ]
    }

    private func editorFont(size: CGFloat) -> NSFont {
        switch design {
        case .system:
            return NSFont.systemFont(ofSize: size, weight: .regular)
        case .serif:
            if let descriptor = NSFont.systemFont(ofSize: size, weight: .regular).fontDescriptor.withDesign(.serif),
               let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
            return NSFont.systemFont(ofSize: size)
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        weak var textView: NSTextView?
        private var highlighting = false

        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !highlighting else { return }
            parent.onTextChange(textView.string)
            applyStyling()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.onSelectionChange?(textView.selectedRange())
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("  ", replacementRange: textView.selectedRange())
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return continueMarkdownList(in: textView)
            }
            return false
        }

        private func continueMarkdownList(in textView: NSTextView) -> Bool {
            let ns = textView.string as NSString
            let selection = textView.selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
            var line = ns.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }
            let patterns = ["^(\\s*)- \\[ \\] ", "^(\\s*)- \\[x\\] ", "^(\\s*)[-*+] ", "^(\\s*)\\d+\\. ", "^(\\s*)> "]
            for (index, pattern) in patterns.enumerated() {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { continue }
                let prefixRange = match.range
                let prefix = (line as NSString).substring(with: prefixRange)
                let content = (line as NSString).substring(from: NSMaxRange(prefixRange))
                if content.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Empty item: clear the marker instead of creating a new one.
                    let fullRange = NSRange(location: lineRange.location, length: (line as NSString).length)
                    parent.controller.replace(range: fullRange, with: "")
                    return true
                }
                var nextPrefix = prefix
                if index == 3, let number = Int(String(prefix.trimmingCharacters(in: .whitespaces).dropLast())) {
                    nextPrefix = prefix.replacingOccurrences(of: "\(number).", with: "\(number + 1).")
                }
                if index == 1 { nextPrefix = prefix.replacingOccurrences(of: "[x]", with: "[ ]") }
                textView.insertText("\n" + nextPrefix, replacementRange: selection)
                return true
            }
            return false
        }

        func applyStyling() {
            guard let textView, let storage = textView.textStorage, let layout = textView.layoutManager else { return }
            highlighting = true
            defer { highlighting = false }
            let palette = parent.palette
            let full = NSRange(location: 0, length: storage.length)
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            layout.removeTemporaryAttribute(.font, forCharacterRange: full)
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
            layout.removeTemporaryAttribute(.underlineColor, forCharacterRange: full)

            let text = storage.string as NSString
            let size = parent.fontSize
            let mono = NSFont.monospacedSystemFont(ofSize: max(11, size - 2), weight: .regular)
            let headingFonts: [CGFloat] = [size * 1.55, size * 1.35, size * 1.16]
            let secondary = NSColor(palette.textSecondary)
            let brand = NSColor(palette.brand)
            let brandInk = NSColor(palette.brandInk)
            let accentBackground = NSColor(palette.softSurface)

            let lineRegex = try? NSRegularExpression(pattern: "(?m)^(#{1,3})\\s.*$")
            lineRegex?.enumerateMatches(in: text as String, range: full) { match, _, _ in
                guard let match else { return }
                let hashes = text.substring(with: NSRange(location: match.range.location, length: min(3, match.range.length)))
                let level = min(3, hashes.filter { $0 == "#" }.count)
                let font = NSFont.systemFont(ofSize: headingFonts[max(0, level - 1)], weight: .semibold)
                layout.addTemporaryAttribute(.font, value: font, forCharacterRange: match.range)
                layout.addTemporaryAttribute(.foregroundColor, value: NSColor(palette.textPrimary), forCharacterRange: match.range)
            }

            // Fenced code blocks.
            let fenceRegex = try? NSRegularExpression(pattern: "(?ms)^```[^\\n]*\\n.*?^```[ \\t]*$")
            fenceRegex?.enumerateMatches(in: text as String, range: full) { match, _, _ in
                guard let match else { return }
                layout.addTemporaryAttribute(.font, value: mono, forCharacterRange: match.range)
                layout.addTemporaryAttribute(.foregroundColor, value: secondary, forCharacterRange: match.range)
                layout.addTemporaryAttribute(.backgroundColor, value: accentBackground.withAlphaComponent(0.55), forCharacterRange: match.range)
            }

            let inlineCode = try? NSRegularExpression(pattern: "`[^`\\n]+`")
            inlineCode?.enumerateMatches(in: text as String, range: full) { match, _, _ in
                guard let match else { return }
                layout.addTemporaryAttribute(.font, value: mono, forCharacterRange: match.range)
                layout.addTemporaryAttribute(.backgroundColor, value: accentBackground, forCharacterRange: match.range)
            }

            let wikilink = try? NSRegularExpression(pattern: "\\[\\[[^\\]\\n]+\\]\\]")
            wikilink?.enumerateMatches(in: text as String, range: full) { match, _, _ in
                guard let match else { return }
                layout.addTemporaryAttribute(.foregroundColor, value: brandInk, forCharacterRange: match.range)
                layout.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: match.range)
                layout.addTemporaryAttribute(.underlineColor, value: brand.withAlphaComponent(0.35), forCharacterRange: match.range)
            }

            let tagRegex = try? NSRegularExpression(pattern: "(?:^|\\s)#[\\p{L}\\p{N}_/-]{2,}")
            tagRegex?.enumerateMatches(in: text as String, range: full) { match, _, _ in
                guard let match else { return }
                layout.addTemporaryAttribute(.foregroundColor, value: brand, forCharacterRange: match.range)
            }

            let markers = try? NSRegularExpression(pattern: "(?m)^(\\s*(?:#{1,6}|>|[-*+]|\\d+\\.|\\[[ xX]\\])\\s?)")
            markers?.enumerateMatches(in: text as String, range: full) { match, _, _ in
                guard let match else { return }
                layout.addTemporaryAttribute(.foregroundColor, value: brand.withAlphaComponent(0.7), forCharacterRange: match.range)
            }

            let emphasis = try? NSRegularExpression(pattern: "(\\*\\*|__|~~|==|\\$\\$?)")
            emphasis?.enumerateMatches(in: text as String, range: full) { match, _, _ in
                guard let match else { return }
                layout.addTemporaryAttribute(.foregroundColor, value: secondary.withAlphaComponent(0.6), forCharacterRange: match.range)
            }
        }
    }
}
