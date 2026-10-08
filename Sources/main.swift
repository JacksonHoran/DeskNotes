import Cocoa
import ServiceManagement

// Every visible note is a plain .md/.txt file in ~/DesktopNotes.
// Edit on screen -> file is saved. Edit the file (you, a script, an AI agent) -> screen updates.

let fm = FileManager.default
let notesDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("DesktopNotes")
let archiveDir = notesDir.appendingPathComponent(".archive")
let layoutURL = notesDir.appendingPathComponent(".layout.json")
let ignoredNames: Set<String> = ["GEMINI.md", "AGENTS.md", "CLAUDE.md", "README.md"]

let palette: [NSColor] = [
    NSColor(srgbRed: 1.00, green: 0.95, blue: 0.60, alpha: 1), // yellow
    NSColor(srgbRed: 1.00, green: 0.80, blue: 0.85, alpha: 1), // pink
    NSColor(srgbRed: 0.80, green: 0.95, blue: 0.80, alpha: 1), // green
    NSColor(srgbRed: 0.80, green: 0.90, blue: 1.00, alpha: 1), // blue
    NSColor(srgbRed: 0.90, green: 0.85, blue: 1.00, alpha: 1), // purple
]

struct Layout: Codable {
    var frames: [String: [Double]] = [:]
    var pinned: Bool = true
}

final class NoteWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: Markdown rendering

enum Markdown {
    static let ink = NSColor(white: 0.12, alpha: 1)
    static let faint = NSColor(white: 0.45, alpha: 1)
    static let toggleScheme = "desknotes-toggle"

    static func render(_ src: String, size: CGFloat = 14) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = src.components(separatedBy: "\n")
        var inCode = false
        let base = NSFont.systemFont(ofSize: size)

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let piece = NSMutableAttributedString()
            let para = NSMutableParagraphStyle()
            para.paragraphSpacing = 3

            if trimmed.hasPrefix("```") { inCode.toggle(); continue }
            if inCode {
                piece.append(NSAttributedString(string: line, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: size * 0.88, weight: .regular),
                    .foregroundColor: ink, .backgroundColor: NSColor(white: 0, alpha: 0.07)]))
                para.paragraphSpacing = 0
            } else if let m = match(#"^(#{1,6})\s+(.*)$"#, line) {
                let level = m[1].count
                let sizes: [CGFloat] = [1.45, 1.25, 1.1, 1.0, 1.0, 1.0]
                let font = NSFont.systemFont(ofSize: size * sizes[level - 1], weight: level <= 2 ? .bold : .semibold)
                piece.append(inline(m[2], font: font, color: ink))
                para.paragraphSpacingBefore = i == 0 ? 0 : 4
                para.paragraphSpacing = 4
            } else if match(#"^\s*([-*_])(\s*\1){2,}\s*$"#, line) != nil {
                piece.append(NSAttributedString(string: "\u{00A0}", attributes: [
                    .font: base, .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor(white: 0, alpha: 0.25)]))
                para.tabStops = [NSTextTab(textAlignment: .left, location: 2000)]
                piece.mutableString.setString("\u{00A0}\t\u{00A0}")
                piece.addAttributes([.font: base, .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                     .strikethroughColor: NSColor(white: 0, alpha: 0.25)],
                                    range: NSRange(location: 0, length: piece.length))
            } else if let m = match(#"^(\s*)[-*+]\s+\[([ xX])\]\s?(.*)$"#, line) {
                let done = m[2] != " "
                indent(para, level: m[1].count / 2, marker: 20)
                let box = NSAttributedString(string: done ? "☑\u{00A0}" : "☐\u{00A0}", attributes: [
                    .font: NSFont.systemFont(ofSize: size * 1.1), .foregroundColor: done ? faint : ink,
                    .link: URL(string: "\(toggleScheme)://\(i)")!])
                piece.append(box)
                let body = inline(m[3], font: base, color: done ? faint : ink)
                if done {
                    body.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                      range: NSRange(location: 0, length: body.length))
                }
                piece.append(body)
            } else if let m = match(#"^(\s*)[-*+]\s+(.*)$"#, line) {
                let level = m[1].count / 2
                indent(para, level: level, marker: 14)
                piece.append(NSAttributedString(string: (level % 2 == 0 ? "•" : "◦") + "\t",
                                                attributes: [.font: base, .foregroundColor: ink]))
                piece.append(inline(m[2], font: base, color: ink))
            } else if let m = match(#"^(\s*)(\d+)[.)]\s+(.*)$"#, line) {
                indent(para, level: m[1].count / 2, marker: 20)
                piece.append(NSAttributedString(string: "\(m[2]).\t", attributes: [.font: base, .foregroundColor: ink]))
                piece.append(inline(m[3], font: base, color: ink))
            } else if let m = match(#"^\s*>\s?(.*)$"#, line) {
                indent(para, level: 0, marker: 12)
                piece.append(NSAttributedString(string: "▎\t", attributes: [.font: base, .foregroundColor: faint]))
                piece.append(inline(m[1], font: italic(base), color: faint))
            } else {
                piece.append(inline(line, font: base, color: ink))
            }

            if i < lines.count - 1 { piece.append(NSAttributedString(string: "\n", attributes: [.font: base])) }
            piece.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: piece.length))
            out.append(piece)
        }
        return out
    }

    static func indent(_ para: NSMutableParagraphStyle, level: Int, marker: CGFloat) {
        let left = CGFloat(level) * 16
        para.firstLineHeadIndent = left
        para.headIndent = left + marker
        para.tabStops = [NSTextTab(textAlignment: .left, location: left + marker)]
        para.defaultTabInterval = marker
    }

    static func italic(_ font: NSFont) -> NSFont {
        let d = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
        return NSFont(descriptor: d, size: font.pointSize) ?? font
    }

    static func inline(_ s: String, font: NSFont, color: NSColor) -> NSMutableAttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: s, options: opts) else {
            return NSMutableAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            var f = font
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if let ip = run.inlinePresentationIntent {
                var traits = f.fontDescriptor.symbolicTraits
                if ip.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if ip.contains(.emphasized) { traits.insert(.italic) }
                f = NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(traits), size: f.pointSize) ?? f
                if ip.contains(.code) {
                    f = .monospacedSystemFont(ofSize: f.pointSize * 0.9, weight: .regular)
                    attrs[.backgroundColor] = NSColor(white: 0, alpha: 0.08)
                }
                if ip.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            if let link = run.link {
                attrs[.link] = link
                attrs[.foregroundColor] = NSColor(srgbRed: 0.1, green: 0.35, blue: 0.8, alpha: 1)
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            attrs[.font] = f
            out.append(NSAttributedString(string: text, attributes: attrs))
        }
        return out
    }

    static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
        }
    }
}

// Read-only rendered view. Clicking a checkbox/link acts on it; clicking anywhere else starts editing.
final class PreviewTextView: NSTextView {
    var onLink: ((URL) -> Void)?
    var onEdit: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let url = link(at: p) { onLink?(url) } else { onEdit?() }
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: .iBeam)
    }

    func link(at p: NSPoint) -> URL? {
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage, ts.length > 0 else { return nil }
        let pt = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        let g = lm.glyphIndex(for: pt, in: tc)
        guard lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).contains(pt) else { return nil }
        let value = ts.attribute(.link, at: lm.characterIndexForGlyph(at: g), effectiveRange: nil)
        return (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
    }
}

final class Note: NSObject, NSTextViewDelegate, NSWindowDelegate {
    let url: URL
    let window: NoteWindow
    let textView: NSTextView
    let editorScroll: NSScrollView
    let preview = PreviewTextView()
    let previewScroll = NSScrollView()
    var lastDiskText: String
    var pendingSave: DispatchWorkItem?
    var editing = false
    weak var app: AppDelegate?

    var name: String { url.lastPathComponent }

    init(url: URL, frame: NSRect, app: AppDelegate) {
        self.url = url
        self.app = app
        lastDiskText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        window = NoteWindow(contentRect: frame,
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        let color = palette[abs(url.lastPathComponent.hashValue) % palette.count]
        window.title = url.deletingPathExtension().lastPathComponent
        window.titlebarAppearsTransparent = true
        window.backgroundColor = color
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.minSize = NSSize(width: 160, height: 100)

        editorScroll = NSTextView.scrollableTextView()
        textView = editorScroll.documentView as! NSTextView
        super.init()

        for scroll in [editorScroll, previewScroll] {
            scroll.drawsBackground = false
            scroll.autohidesScrollers = true
            scroll.hasVerticalScroller = true
            scroll.autoresizingMask = [.width, .height]
        }
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = Markdown.ink
        textView.insertionPointColor = .black
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = lastDiskText
        textView.delegate = self

        preview.drawsBackground = false
        preview.isEditable = false
        preview.isSelectable = false
        preview.linkTextAttributes = [:]  // use the renderer's own link styling
        preview.textContainerInset = NSSize(width: 8, height: 6)
        preview.isVerticallyResizable = true
        preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true
        preview.onEdit = { [weak self] in self?.showEditor() }
        preview.onLink = { [weak self] link in self?.handle(link) }
        previewScroll.documentView = preview

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        editorScroll.frame = container.bounds
        previewScroll.frame = container.bounds
        preview.frame = NSRect(origin: .zero, size: previewScroll.contentSize)
        container.addSubview(editorScroll)
        container.addSubview(previewScroll)
        window.contentView = container
        window.delegate = self
        applyLevel(pinned: app.layout.pinned)
        showPreview()
        window.orderFront(nil)
    }

    func applyLevel(pinned: Bool) {
        window.level = pinned
            ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            : .floating
    }

    // MARK: Modes

    func showPreview() {
        editing = false
        let text = textView.string
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preview.textStorage?.setAttributedString(NSAttributedString(string: "Click to write…", attributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: Markdown.faint]))
        } else {
            preview.textStorage?.setAttributedString(Markdown.render(text))
        }
        editorScroll.isHidden = true
        previewScroll.isHidden = false
        window.invalidateCursorRects(for: preview)
    }

    func showEditor() {
        editing = true
        previewScroll.isHidden = true
        editorScroll.isHidden = false
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    func toggleMode() { editing ? showPreview() : showEditor() }

    func handle(_ link: URL) {
        if link.scheme == Markdown.toggleScheme, let line = Int(link.host ?? "") {
            var lines = textView.string.components(separatedBy: "\n")
            guard line < lines.count else { return }
            let l = lines[line]
            if let r = l.range(of: "[ ]") { lines[line] = l.replacingCharacters(in: r, with: "[x]") }
            else if let r = l.range(of: "[x]") ?? l.range(of: "[X]") { lines[line] = l.replacingCharacters(in: r, with: "[ ]") }
            textView.string = lines.joined(separator: "\n")
            saveNow()
            showPreview()
        } else {
            NSWorkspace.shared.open(link)
        }
    }

    // Esc returns to preview.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { saveNow(); showPreview(); return true }
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard editing else { return }
        saveNow()
        showPreview()
    }

    // Local edits: save shortly after typing stops.
    func textDidChange(_ notification: Notification) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let text = textView.string
        guard text != lastDiskText else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            lastDiskText = text
        } catch { NSSound.beep() }
    }

    // External edits: pick up whatever is on disk unless the user is mid-edit.
    func reloadIfChanged() {
        guard pendingSave == nil else { return }
        guard let disk = try? String(contentsOf: url, encoding: .utf8), disk != lastDiskText else { return }
        lastDiskText = disk
        guard textView.string != disk else { return }
        let sel = textView.selectedRange()
        textView.string = disk
        let loc = min(sel.location, (disk as NSString).length)
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        if !editing { showPreview() }
        flash()
    }

    func flash() {
        guard let view = window.contentView else { return }
        view.wantsLayer = true
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0.4; anim.toValue = 1; anim.duration = 0.5
        view.layer?.add(anim, forKey: "flash")
    }

    // Closing a note archives its file (recoverable in ~/DesktopNotes/.archive).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        saveNow()
        try? fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = archiveDir.appendingPathComponent("\(stamp)-\(name)")
        try? fm.moveItem(at: url, to: dest)
        app?.forget(self)
        return true
    }

    func windowDidMove(_ notification: Notification) { app?.recordFrame(of: self) }
    func windowDidResize(_ notification: Notification) { app?.recordFrame(of: self) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var layout = Layout()
    var notes: [String: Note] = [:]
    var statusItem: NSStatusItem!
    var pinItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var layoutSave: DispatchWorkItem?

    func applicationDidFinishLaunching(_ n: Notification) {
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        writeAgentInstructions()
        if let data = try? Data(contentsOf: layoutURL),
           let l = try? JSONDecoder().decode(Layout.self, from: data) { layout = l }

        buildMainMenu()
        buildStatusItem()

        if noteFiles().isEmpty {
            try? "# Today\n\n- [ ] Click here and start typing\n".write(
                to: notesDir.appendingPathComponent("Today.md"), atomically: true, encoding: .utf8)
        }
        sync()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.sync() }
    }

    func applicationWillTerminate(_ n: Notification) {
        notes.values.forEach { $0.saveNow() }
        writeLayout()
    }

    func noteFiles() -> [URL] {
        let items = (try? fm.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil,
                                                 options: [.skipsHiddenFiles])) ?? []
        return items.filter {
            ["md", "txt"].contains($0.pathExtension.lowercased()) && !ignoredNames.contains($0.lastPathComponent)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func sync() {
        let files = noteFiles()
        let names = Set(files.map { $0.lastPathComponent })
        for (name, note) in notes where !names.contains(name) {
            note.window.delegate = nil
            note.window.close()
            notes[name] = nil
        }
        for url in files {
            if let note = notes[url.lastPathComponent] {
                note.reloadIfChanged()
            } else {
                notes[url.lastPathComponent] = Note(url: url, frame: frame(for: url.lastPathComponent, index: notes.count), app: self)
            }
        }
    }

    func frame(for name: String, index: Int) -> NSRect {
        if let f = layout.frames[name], f.count == 4 { return NSRect(x: f[0], y: f[1], width: f[2], height: f[3]) }
        let screen = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let col = index % 4, row = (index / 4) % 3
        return NSRect(x: screen.maxX - 280 - CGFloat(col) * 270,
                      y: screen.maxY - 260 - CGFloat(row) * 270, width: 250, height: 230)
    }

    func forget(_ note: Note) {
        notes[note.name] = nil
        layout.frames[note.name] = nil
        scheduleLayoutSave()
    }

    func recordFrame(of note: Note) {
        let f = note.window.frame
        layout.frames[note.name] = [f.origin.x, f.origin.y, f.size.width, f.size.height]
        scheduleLayoutSave()
    }

    func scheduleLayoutSave() {
        layoutSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeLayout() }
        layoutSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func writeLayout() {
        if let data = try? JSONEncoder().encode(layout) { try? data.write(to: layoutURL) }
    }

    // MARK: Menus

    func buildMainMenu() {
        // Needed so Cmd-C/V/X/A/Z work in the text views even though the app has no Dock icon.
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit DeskNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "n").target = self
        edit.addItem(withTitle: "Toggle Edit/Preview", action: #selector(togglePreview), keyEquivalent: "e").target = self
        edit.addItem(withTitle: "Close Note", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "DeskNotes")
        let menu = NSMenu()
        menu.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "Bring Notes to Front", action: #selector(bringToFront), keyEquivalent: "").target = self
        menu.addItem(.separator())
        pinItem = menu.addItem(withTitle: "Pin to Desktop (behind windows)", action: #selector(togglePin), keyEquivalent: "")
        pinItem.target = self
        pinItem.state = layout.pinned ? .on : .off
        loginItem = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Open Notes Folder", action: #selector(openFolder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DeskNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func newNote() {
        var n = 1
        var url = notesDir.appendingPathComponent("Note.md")
        while fm.fileExists(atPath: url.path) { n += 1; url = notesDir.appendingPathComponent("Note \(n).md") }
        try? "".write(to: url, atomically: true, encoding: .utf8)
        sync()
        if let note = notes[url.lastPathComponent] {
            note.showEditor()
        }
    }

    @objc func togglePreview() {
        notes.values.first { $0.window.isKeyWindow }?.toggleMode()
    }

    @objc func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        notes.values.forEach { $0.window.orderFrontRegardless() }
    }

    @objc func togglePin() {
        layout.pinned.toggle()
        pinItem.state = layout.pinned ? .on : .off
        notes.values.forEach { $0.applyLevel(pinned: layout.pinned) }
        writeLayout()
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func openFolder() { NSWorkspace.shared.open(notesDir) }

    func writeAgentInstructions() {
        let url = notesDir.appendingPathComponent("GEMINI.md")
        guard !fm.fileExists(atPath: url.path) else { return }
        let text = """
        # Desktop notes (for AI agents)

        This folder is mirrored live onto the user's macOS desktop by the DeskNotes app.

        - Every `*.md` / `*.txt` file here (except this file, AGENTS.md, CLAUDE.md, README.md and dotfiles) is one sticky note.
        - The filename (without extension) is the note's title.
        - To update a note: edit/overwrite its file. The on-screen note refreshes within ~1 second.
        - To add a note: create a new `.md` file. To remove one: delete the file.
        - The user also types into these notes directly, so always re-read a file right before editing it,
          and change only the parts you need to (don't overwrite the user's text).
        - Keep notes short — they are small sticky notes. Plain Markdown text; `- [ ]` / `- [x]` for todos.
        """
        try? text.write(to: url, atomically: true, encoding: .utf8)
        try? fm.createSymbolicLink(at: notesDir.appendingPathComponent("AGENTS.md"), withDestinationURL: url)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
