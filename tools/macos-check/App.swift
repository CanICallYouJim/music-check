import AppKit
import UniformTypeIdentifiers

private let ink = NSColor(calibratedRed: 21/255, green: 35/255, blue: 45/255, alpha: 1)
private let mint = NSColor(calibratedRed: 99/255, green: 215/255, blue: 193/255, alpha: 1)
private let muted = NSColor(calibratedRed: 145/255, green: 168/255, blue: 170/255, alpha: 1)


func musicDirectory(_ urls: [URL]) -> URL? {
    guard urls.count == 1, let url = urls.first, url.isFileURL else { return nil }
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { return nil }
    return url.standardizedFileURL
}

struct CheckResult: Decodable {
    let output: String
    let total, checked, fresh, cached, errors, warnings, incomplete: Int
    let interrupted: Bool
    let error: String
    var report_interrupted: Bool? = nil
    var message: String {
        if report_interrupted == true { return "Результаты проверки сохранены. Подготовка фрагментов остановлена; откройте отчёт." }
        if interrupted && output.isEmpty { return "Проверка остановлена. Можно запустить её снова." }
        if interrupted { return "Остановлено. Проверено: \(checked) из \(total). Готовые результаты сохранены." }
        if error.contains("operation not permitted") || error.contains("permission denied") {
            return "Нет доступа к папке. Нажмите «Выбрать…» и выберите её заново."
        }
        if error.contains("в выбранной папке нет аудиофайлов") {
            return "В этой папке не найдено музыки. Выберите другую папку или включите «Включая подпапки»."
        }
        if !error.isEmpty { return "Не удалось закончить проверку. Причина — в подробностях." }
        return "Проверено: \(checked). Требует внимания: \(errors). Стоит прослушать: \(warnings)." + (incomplete > 0 ? " Не проверено до конца: \(incomplete)." : "")
    }
}

func musicDroppedDirectory(_ info: NSDraggingInfo) -> URL? {
    let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    return musicDirectory(urls)
}

final class FolderView: NSView {
    var accept: ((URL) -> Void)?
    var available: (() -> Bool)?
    var hover: ((Bool) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.backgroundColor = ink.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    private func folder(_ sender: NSDraggingInfo) -> URL? {
        guard available?() == true else { return nil }
        return musicDroppedDirectory(sender)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = folder(sender) != nil
        hover?(valid)
        return valid ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { hover?(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hover?(false)
        guard let url = folder(sender) else { return false }
        accept?(url)
        return true
    }
}

final class FolderBox: NSComboBox {
    var accept: ((URL) -> Void)?
    var canDrop: (() -> Bool)?
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        canDrop?() == true && musicDroppedDirectory(sender) != nil ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard canDrop?() == true, let folder = musicDroppedDirectory(sender) else { return false }
        accept?(folder)
        return true
    }
}

final class FolderDropZone: NSView {
    private let icon = NSWorkspace.shared.icon(for: .folder)
    var highlighted = false { didSet { if highlighted != oldValue { refresh() } } }
    var selected = false { didSet { if selected != oldValue { refresh() } } }

    private var message: String {
        if highlighted { return "Отпустите, чтобы выбрать" }
        return selected ? "Папка выбрана" : "Перетащите папку сюда"
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func refresh() {
        setAccessibilityLabel(message)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        let fill = highlighted
            ? NSColor(calibratedRed: 35/255, green: 71/255, blue: 72/255, alpha: 1)
            : NSColor(calibratedRed: 25/255, green: 45/255, blue: 55/255, alpha: 1)
        fill.setFill()
        outline.fill()
        (highlighted || selected ? mint : muted).setStroke()
        outline.lineWidth = highlighted ? 2 : 1
        if !highlighted && !selected { outline.setLineDash([5, 4], count: 2, phase: 0) }
        outline.stroke()

        icon.draw(in: NSRect(x: bounds.midX - 63, y: bounds.midY - 51, width: 126, height: 126))
        let title = message as NSString
        let style: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 19, weight: .semibold),
            .foregroundColor: highlighted || selected ? mint : NSColor.white
        ]
        title.draw(at: NSPoint(x: bounds.midX - title.size(withAttributes: style).width / 2, y: bounds.midY - 78), withAttributes: style)
    }
}

final class BrandView: NSView {
    private let sprite: NSImage?
    private var tracking: NSTrackingArea?
    private var timer: Timer?
    private var start: TimeInterval = 0
    private var frameIndex = 0
    init(frame: NSRect, resource: URL?) {
        sprite = resource.flatMap { NSImage(contentsOf: $0) }
        super.init(frame: frame)
        if let sprite { sprite.size = NSSize(width: 2880, height: 1521) }
        setAccessibilityLabel("by IG")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        if let tracking { addTrackingArea(tracking) }
    }
    override func mouseEntered(with event: NSEvent) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, sprite != nil else { return }
        reset()
        start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1/60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - self.start
            if elapsed >= 3.5 { self.reset(); return }
            self.frameIndex = min(104, Int(elapsed * 30))
            self.needsDisplay = true
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override func mouseExited(with event: NSEvent) { reset() }
    private func reset() { timer?.invalidate(); timer = nil; frameIndex = 0; needsDisplay = true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { reset() }
    }
    override func draw(_ dirtyRect: NSRect) {
        ("by" as NSString).draw(at: NSPoint(x: 0, y: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: muted])
        guard let sprite else { return }
        let height = 48.0 * 169 / 192
        let source = NSRect(x: (frameIndex % 15) * 192, y: (8 - frameIndex / 15) * 169, width: 192, height: 169)
        sprite.draw(in: NSRect(x: 22, y: (62-height)/2, width: 48, height: height), from: source, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }
    deinit { timer?.invalidate() }
}


struct UpdateStatus: Decodable {
    let current: String
    let latest: String
    let available: Bool
    let notes: String
    let error: String
    let target: String
}

extension UpdateStatus {
    private enum CodingKeys: String, CodingKey { case current, latest, available, notes, error, target }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        current = try values.decodeIfPresent(String.self, forKey: .current) ?? ""
        latest = try values.decodeIfPresent(String.self, forKey: .latest) ?? ""
        available = try values.decodeIfPresent(Bool.self, forKey: .available) ?? false
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        error = try values.decodeIfPresent(String.self, forKey: .error) ?? ""
        target = try values.decodeIfPresent(String.self, forKey: .target) ?? ""
    }
}

struct UpdateInstallResult: Decodable {
    let target: String
    let error: String
}

func versionBanner(_ update: UpdateStatus, fallback: String) -> String {
    let current = update.current.isEmpty ? fallback : update.current
    if update.available { return "Версия \(current) · Доступно обновление \(update.latest)" }
    if !update.target.isEmpty { return "Версия \(current) · Обновление готово к запуску" }
    if !update.error.isEmpty { return "Версия \(current) · Не удалось проверить обновления" }
    return "Версия \(current) · Установлена последняя версия"
}


struct CheckProgress {
    let message: String
    let percent: Double?
}

// The process pipe may split a UTF-8 character or a progress line between reads.
struct CheckProgressParser {
    private var pending = Data()
    private var discardingLine = false
    private var reportStarted = false
    private var reportPercent = 0
    mutating func append(_ data: Data, finished: Bool = false) -> [CheckProgress] {
        pending.append(data)
        var updates: [CheckProgress] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<newline], as: UTF8.self).trimmingCharacters(in: .newlines)
            pending.removeSubrange(...newline)
            if !discardingLine, let update = parse(line) { updates.append(update) }
            discardingLine = false
        }
        if finished && !pending.isEmpty {
            if !discardingLine, let update = parse(String(decoding: pending, as: UTF8.self)) { updates.append(update) }
            pending.removeAll()
        } else if pending.count > 65_536 {
            pending.removeAll()
            discardingLine = true
        }
        return updates
    }
    private mutating func parse(_ line: String) -> CheckProgress? {
        let prefix = "[Отчёт "
        if line.hasPrefix(prefix), let closing = line.range(of: "%]"),
           let value = Int(line[line.index(line.startIndex, offsetBy: prefix.count)..<closing.lowerBound]), (0...100).contains(value) {
            reportStarted = true
            reportPercent = max(reportPercent, value)
            let detail = line[closing.upperBound...].trimmingCharacters(in: .whitespaces)
            return CheckProgress(message: "Отчёт: \(reportPercent)% · \(detail)", percent: Double(reportPercent))
        }
        if line.hasPrefix("Подготовка встроенных фрагментов") {
            reportStarted = true
            return CheckProgress(message: "Готовим отчёт и короткие фрагменты для прослушивания…", percent: Double(reportPercent))
        }
        guard !reportStarted, line.hasPrefix("["), let closing = line.firstIndex(of: "]") else { return nil }
        let counts = line[line.index(after: line.startIndex)..<closing].split(separator: "/")
        guard counts.count == 2, let current = Int(counts[0]), let total = Int(counts[1]), current > 0, current <= total else { return nil }
        return CheckProgress(message: "Проверяем запись \(current) из \(total). Неизменившиеся записи берём из истории.", percent: nil)
    }
}

// Keep the most recent diagnostics on the Mac, even after the window closes.
// Compact by 2 MiB only at the limit, rather than rewriting on every pipe read.
final class CheckLogWriter {
    static let limit = 4 * 1024 * 1024
    private let file: FileHandle
    private var size = 0
    private let lock = NSLock()
    init(url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        // Atomic replacement avoids truncating a prior log linked to another file.
        try Data().write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        file = try FileHandle(forUpdating: url)
    }
    func append(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        if data.count >= Self.limit {
            try file.truncate(atOffset: 0)
            try file.seek(toOffset: 0)
            let tail = Data(data.suffix(Self.limit))
            try file.write(contentsOf: tail)
            size = tail.count
        } else {
            if size + data.count > Self.limit {
                let keep = min(size, min(Self.limit / 2, Self.limit - data.count))
                try file.seek(toOffset: UInt64(size - keep))
                let tail = try file.readToEnd() ?? Data()
                try file.truncate(atOffset: 0)
                try file.seek(toOffset: 0)
                try file.write(contentsOf: tail)
                size = tail.count
            }
            try file.seekToEnd()
            try file.write(contentsOf: data)
            size += data.count
        }
    }
    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        try file.close()
    }
}

final class CheckApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSComboBoxDelegate {
    private var window: NSWindow!
    private let folders = FolderBox(frame: NSRect(x: 28, y: 218, width: 486, height: 28))
    private let dropZone = FolderDropZone(frame: NSRect(x: 28, y: 262, width: 604, height: 222))
    private let recursive = NSButton(checkboxWithTitle: "Включая подпапки", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator(frame: NSRect(x: 28, y: 91, width: 604, height: 12))
    private let log = NSTextView()
    private let scroll = NSScrollView(frame: NSRect(x: 28, y: 262, width: 604, height: 222))
    private var browse: NSButton!
    private var start: NSButton!
    private var stop: NSButton!
    private var report: NSButton!
    private var journal: NSButton!
    private var anotherFolder: NSButton!
    private var process: Process?
    private var reportURL: URL?
    private var pendingFolder: URL?
    private var quitAfterStop = false
    private var logBytes = Data()
    private var progressParser = CheckProgressParser()
    private var checkLogWriter: CheckLogWriter?
    private var logWriteFailed = false
    private var checkLogURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MusicCheck/last-check.log") }
    private var versionLabel: NSTextField!
    private var updateBanner: NSView!
    private var updateButton: NSButton!
    private var updateTimer: Timer?
    private var checkProcess: Process?
    private let checkCleanup = DispatchGroup()
    private var updateProcess: Process?
    private var updateAvailable = false
    private var cachedTarget = ""
    private var openingUpdate = false
    private var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.4" }
    private var busy: Bool { process != nil || updateProcess != nil || openingUpdate }
    private var history: [String] {
        get { UserDefaults.standard.stringArray(forKey: "RecentMusicFolders") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(6)), forKey: "RecentMusicFolders") }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 600), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Проверка музыки"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        let root = FolderView(frame: NSRect(x: 0, y: 0, width: 660, height: 600))
        root.available = { [weak self] in self?.busy == false }
        root.accept = { [weak self] in self?.select($0) }
        root.hover = { [weak self] active in self?.dropZone.highlighted = active }
        window.contentView = root
        updateBanner = NSView(frame: NSRect(x: 20, y: 550, width: 620, height: 38))
        updateBanner.wantsLayer = true
        updateBanner.layer?.cornerRadius = 8
        updateBanner.layer?.backgroundColor = mint.withAlphaComponent(0.08).cgColor
        updateBanner.layer?.borderColor = mint.withAlphaComponent(0.35).cgColor
        updateBanner.layer?.borderWidth = 1
        updateBanner.isHidden = true
        root.addSubview(updateBanner)
        versionLabel = label("Версия \(currentVersion) · Проверяем обновления…", frame: NSRect(x: 28, y: 558, width: 450, height: 24), size: 12, color: muted)
        versionLabel.lineBreakMode = .byTruncatingTail
        updateButton = button("Обновить", frame: NSRect(x: 490, y: 554, width: 142, height: 30), action: #selector(installUpdate))
        updateButton.isHidden = true
        updateButton.isEnabled = false
        _ = label("Проверьте музыку перед выступлением", frame: NSRect(x: 28, y: 502, width: 604, height: 36), size: 26, bold: true)
        root.addSubview(dropZone)
        folders.isEditable = true
        folders.completes = false
        folders.delegate = self
        folders.numberOfVisibleItems = 6
        folders.setAccessibilityLabel("Папка с музыкой")
        folders.registerForDraggedTypes([.fileURL])
        folders.canDrop = { [weak self] in self?.busy == false }
        folders.accept = { [weak self] in self?.select($0) }
        root.addSubview(folders)
        refreshFolders()
        browse = button("Выбрать…", frame: NSRect(x: 526, y: 216, width: 106, height: 32), action: #selector(choose))
        recursive.frame = NSRect(x: 28, y: 182, width: 300, height: 24)
        recursive.state = .on
        root.addSubview(recursive)
        _ = label("Отчёт — в подпапке «Проверка музыки».", frame: NSRect(x: 28, y: 154, width: 604, height: 22), size: 12, color: muted)
        status.frame = NSRect(x: 28, y: 109, width: 604, height: 42)
        status.font = .systemFont(ofSize: 14)
        status.textColor = .white
        root.addSubview(status)
        progress.style = .bar
        progress.isIndeterminate = true
        progress.isDisplayedWhenStopped = false
        root.addSubview(progress)
        journal = button("Открыть журнал", frame: NSRect(x: 490, y: 180, width: 142, height: 30), action: #selector(openJournal))
        journal.isEnabled = FileManager.default.fileExists(atPath: checkLogURL.path)
        journal.toolTip = "Журнал последней проверки сохраняется на этом Mac, а не на флешке."
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.isHidden = true
        scroll.setAccessibilityLabel("Журнал проверки")
        log.isEditable = false
        log.isSelectable = true
        log.isRichText = false
        log.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        log.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        log.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1)
        log.textContainerInset = NSSize(width: 10, height: 10)
        log.autoresizingMask = [.width]
        log.isVerticallyResizable = true
        log.textContainer?.widthTracksTextView = true
        log.frame = NSRect(origin: .zero, size: scroll.contentSize)
        log.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        log.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = log
        root.addSubview(scroll)
        root.addSubview(BrandView(frame: NSRect(x: 28, y: 22, width: 112, height: 62), resource: Bundle.main.url(forResource: "brand", withExtension: "png")))
        anotherFolder = button("Другая папка", frame: NSRect(x: 148, y: 38, width: 136, height: 32), action: #selector(showFolderSelection))
        anotherFolder.isHidden = true
        report = button("Открыть отчёт", frame: NSRect(x: 288, y: 38, width: 126, height: 32), action: #selector(openReport))
        report.isEnabled = false
        stop = button("Остановить", frame: NSRect(x: 418, y: 38, width: 108, height: 32), action: #selector(cancel))
        stop.isEnabled = false
        start = button("Проверить", frame: NSRect(x: 530, y: 38, width: 102, height: 32), action: #selector(check))
        start.keyEquivalent = "\r"
        start.contentTintColor = mint
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Завершить проверку музыки", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        let edit = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Правка")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выделить всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        menu.addItem(edit)
        NSApp.mainMenu = menu
        if let index = CommandLine.arguments.firstIndex(of: "--folder"), index + 1 < CommandLine.arguments.count,
           let folder = musicDirectory([URL(fileURLWithPath: CommandLine.arguments[index + 1])]) { pendingFolder = folder }
        if CommandLine.arguments.contains("--recursive=false") { recursive.state = .off }
        if let pendingFolder { select(pendingFolder); self.pendingFolder = nil }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        checkForUpdates(atLaunch: true)
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }
    @discardableResult private func label(_ text: String, frame: NSRect, size: CGFloat, bold: Bool = false, color: NSColor = .white) -> NSTextField {
        let view = NSTextField(labelWithString: text)
        view.frame = frame
        view.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        view.textColor = color
        window.contentView?.addSubview(view)
        return view
    }
    private func button(_ title: String, frame: NSRect, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = frame
        button.bezelStyle = .rounded
        window.contentView?.addSubview(button)
        return button
    }
    private func refreshFolders() {
        let current = folders.stringValue
        folders.removeAllItems()
        folders.addItems(withObjectValues: history)
        folders.stringValue = current.isEmpty ? (history.first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music").path) : current
    }
    func controlTextDidChange(_ notification: Notification) {
        dropZone.selected = false
        if !dropZone.isHidden { status.stringValue = "" }
    }
    func comboBoxSelectionDidChange(_ notification: Notification) {
        let path = folders.objectValueOfSelectedItem as? String ?? ""
        dropZone.selected = !path.isEmpty && musicDirectory([URL(fileURLWithPath: path)]) != nil
        if !dropZone.isHidden { status.stringValue = "" }
    }
    private func select(_ folder: URL) {
        guard !busy else { return }
        showFolderSelection()
        folders.stringValue = folder.path
        dropZone.selected = true
        status.stringValue = "Папка выбрана. Нажмите «Проверить»."
    }
    @objc private func showFolderSelection() {
        guard !busy else { return }
        dropZone.highlighted = false
        dropZone.selected = false
        dropZone.isHidden = false
        scroll.isHidden = true
        anotherFolder.isHidden = true
        status.stringValue = ""
    }
    private func showWorkLog() {
        dropZone.isHidden = true
        scroll.isHidden = false
        anotherFolder.isHidden = false
    }
    @objc private func choose() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        panel.directoryURL = musicDirectory([URL(fileURLWithPath: folders.stringValue)])
        panel.beginSheetModal(for: window) { [weak self] reply in
            if reply == .OK, let url = musicDirectory(panel.urls) { self?.select(url) }
        }
    }
    @objc private func check() {
        guard !busy else { return }
        let path = (folders.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !path.isEmpty, let folder = musicDirectory([URL(fileURLWithPath: path)]) else {
            status.stringValue = "Выберите существующую папку с музыкой."
            return
        }
        guard let resources = Bundle.main.resourceURL, let executable = Bundle.main.executableURL else { return }
        showWorkLog()
        logBytes.removeAll()
        log.string = ""
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("music-check-" + UUID().uuidString)
        do { try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true) }
        catch { status.stringValue = "Не удалось подготовить запуск. Проверьте свободное место и доступ к диску."; appendLog(Data("\(error)\n".utf8)); return }
        let resultURL = temp.appendingPathComponent("result.json")
        let task = Process()
        task.executableURL = executable.deletingLastPathComponent().appendingPathComponent("music-check-engine")
        task.arguments = ["--folder", folder.path, "--recursive=\(recursive.state == .on)", "--tools", resources.appendingPathComponent("tools").path, "--result", resultURL.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        progressParser = CheckProgressParser()
        logWriteFailed = false
        journal.title = "Открыть журнал"
        do {
            checkLogWriter = try CheckLogWriter(url: checkLogURL)
            journal.isEnabled = true
        } catch {
            checkLogWriter = nil
            recordLogFailure(error)
        }
        let writer = checkLogWriter
        reportURL = nil
        report.isEnabled = false
        do { try task.run() }
        catch {
            try? FileManager.default.removeItem(at: temp)
            status.stringValue = "Не удалось запустить проверку. Причина — в подробностях."
            appendLog(Data("\(error)\n".utf8))
            try? checkLogWriter?.close()
            checkLogWriter = nil
            return
        }
        process = task
        setBusy(true)
        history = [folder.path] + history.filter { $0 != folder.path }
        refreshFolders()
        status.stringValue = "Проверяем музыку. Это может занять время; исходные файлы не меняются."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                var writeError: Error?
                do { try writer?.append(data) } catch { writeError = error }
                DispatchQueue.main.async { [weak self] in
                    self?.appendLog(data, persist: false)
                    if let writeError { self?.recordLogFailure(writeError) }
                }
            }
            task.waitUntilExit()
            var closeError: Error?
            do { try writer?.close() } catch { closeError = error }
            let result = (try? Data(contentsOf: resultURL)).flatMap { try? JSONDecoder().decode(CheckResult.self, from: $0) }
            try? FileManager.default.removeItem(at: temp)
            DispatchQueue.main.async { [weak self] in
                self?.checkLogWriter = nil
                if let closeError { self?.recordLogFailure(closeError) }
                self?.applyProgress(self?.progressParser.append(Data(), finished: true) ?? [])
                self?.finished(result)
            }
        }
    }
    private func recordLogFailure(_ error: Error) {
        guard !logWriteFailed else { return }
        logWriteFailed = true
        journal.title = "Журнал недоступен"
        journal.isEnabled = false
        journal.toolTip = "Не удалось сохранить журнал. Подробности пока доступны в этом окне."
        appendLog(Data("Не удалось сохранить журнал: \(error)\n".utf8), persist: false)
    }
    private func applyProgress(_ updates: [CheckProgress]) {
        guard process != nil, stop.isEnabled else { return }
        for update in updates {
            status.stringValue = update.message
            status.toolTip = update.message
            if let percent = update.percent {
                progress.stopAnimation(nil)
                progress.isIndeterminate = false
                progress.isDisplayedWhenStopped = true
                progress.isHidden = false
                progress.minValue = 0
                progress.maxValue = 100
                progress.doubleValue = percent
            }
        }
    }
    private func appendLog(_ data: Data, persist: Bool = true) {
        if persist {
            do { try checkLogWriter?.append(data) } catch { recordLogFailure(error) }
        }
        logBytes.append(data)
        if logBytes.count > 262_144 { logBytes.removeFirst(logBytes.count - 262_144) }
        log.string = String(decoding: logBytes, as: UTF8.self)
        log.scrollToEndOfDocument(nil)
        applyProgress(progressParser.append(data))
    }

    private func setBusy(_ value: Bool) {
        folders.isEnabled = !value
        recursive.isEnabled = !value
        browse.isEnabled = !value
        start.isEnabled = !value
        anotherFolder.isEnabled = !value
        stop.isEnabled = value && (process != nil || updateProcess != nil)
        report.isEnabled = !value && reportURL != nil
        updateButton.isEnabled = !value && checkProcess == nil && updateAvailable
        progress.isHidden = !value
        if value {
            progress.isDisplayedWhenStopped = false
            progress.isIndeterminate = true
            progress.doubleValue = 0
            progress.startAnimation(nil)
        } else { progress.stopAnimation(nil) }
    }
    private func finished(_ result: CheckResult?) {
        process = nil
        setBusy(false)
        status.stringValue = result?.message ?? "Проверка прервалась. Подробности сохранены в журнале ниже; запустите её снова."
        if let result {
            if !result.error.isEmpty { appendLog(Data("\n\(result.error)\n".utf8)) }
            if !result.output.isEmpty { reportURL = URL(fileURLWithPath: result.output) }
        }
        report.isEnabled = reportURL != nil
        if logWriteFailed { status.stringValue += " Журнал не сохранён; подробности доступны в этом окне." }
        if quitAfterStop { NSApp.reply(toApplicationShouldTerminate: true) }
    }
    @objc private func cancel() {
        if let updateProcess, updateProcess.isRunning {
            stop.isEnabled = false
            status.stringValue = "Отменяем загрузку обновления…"
            updateProcess.interrupt()
            return
        }
        guard let process, process.isRunning else { return }
        stop.isEnabled = false
        status.stringValue = "Останавливаем проверку и сохраняем готовые результаты…"
        process.interrupt()
    }
    @objc private func openReport() { if let reportURL { NSWorkspace.shared.open(reportURL) } }
    @objc private func openJournal() {
        if !NSWorkspace.shared.open(checkLogURL) { status.stringValue = "Не удалось открыть журнал. Он сохранён на Mac: \(checkLogURL.path)" }
    }
    // The updater runs separately from music checking. Checking availability
    // never blocks the window, and installation cannot start while music is busy.
    private func launchUpdateCommand(_ mode: String, refresh: Bool = false, completion: @escaping (Data?, Int32) -> Void) throws -> Process {
        guard let executable = Bundle.main.executableURL else {
            throw NSError(domain: "IGUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не найден движок обновления."])
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ig-update-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let resultURL = temporary.appendingPathComponent("result.json")
        let task = Process()
        task.executableURL = executable.deletingLastPathComponent().appendingPathComponent("music-check-engine")
        task.arguments = [mode, "--result", resultURL.path]
        if refresh { task.arguments?.append("--refresh") }
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do { try task.run() }
        catch { try? FileManager.default.removeItem(at: temporary); throw error }
        let cleanup = mode == "--update-status" ? checkCleanup : nil
        cleanup?.enter()
        DispatchQueue.global(qos: .utility).async {
            task.waitUntilExit()
            let data = try? Data(contentsOf: resultURL)
            try? FileManager.default.removeItem(at: temporary)
            cleanup?.leave()
            DispatchQueue.main.async { completion(data, task.terminationStatus) }
        }
        return task
    }
    private func checkForUpdates(atLaunch: Bool = false) {
        guard checkProcess == nil, updateProcess == nil, !openingUpdate, !quitAfterStop else { return }
        do {
            checkProcess = try launchUpdateCommand("--update-status", refresh: !atLaunch) { [weak self] data, _ in
                guard let self else { return }
                self.checkProcess = nil
                guard !self.quitAfterStop else { return }
                defer { self.updateButton.isEnabled = self.updateAvailable && !self.busy }
                guard let data, let update = try? JSONDecoder().decode(UpdateStatus.self, from: data) else {
                    if !self.updateAvailable {
                        self.versionLabel.stringValue = "Версия \(self.currentVersion) · Не удалось проверить обновления"
                    }
                    return
                }
                if !update.error.isEmpty && self.updateAvailable { return }
                self.versionLabel.stringValue = versionBanner(update, fallback: self.currentVersion)
                self.versionLabel.toolTip = update.error.isEmpty ? update.notes : update.error
                self.cachedTarget = update.target
                self.updateAvailable = update.available || !update.target.isEmpty
                self.updateBanner.isHidden = !self.updateAvailable
                self.versionLabel.textColor = self.updateAvailable ? mint : muted
                self.updateButton.isHidden = !self.updateAvailable
                self.updateButton.title = update.target.isEmpty ? "Обновить" : "Перезапустить"
                if atLaunch && !update.target.isEmpty && !self.busy { self.openUpdatedApp(update.target) }
            }
            updateButton.isEnabled = false
        } catch {
            if !updateAvailable { versionLabel.stringValue = "Версия \(currentVersion) · Не удалось проверить обновления" }
        }
    }
    @objc private func installUpdate() {
        guard !busy, checkProcess == nil, updateAvailable else { return }
        if !cachedTarget.isEmpty { openUpdatedApp(cachedTarget); return }
        do {
            updateProcess = try launchUpdateCommand("--install-update") { [weak self] data, exitCode in
                guard let self else { return }
                self.updateProcess = nil
                self.setBusy(false)
                if self.quitAfterStop { NSApp.reply(toApplicationShouldTerminate: true); return }
                guard let data, let result = try? JSONDecoder().decode(UpdateInstallResult.self, from: data) else {
                    self.status.stringValue = exitCode == 2 ? "Загрузка отменена. Текущая версия сохранена." : "Не удалось установить обновление. Текущая версия сохранена."
                    return
                }
                if !result.error.isEmpty {
                    self.showWorkLog()
                    self.appendLog(Data("\(result.error)\n".utf8))
                    self.status.stringValue = exitCode == 2 ? "Загрузка отменена. Текущая версия сохранена." : "Не удалось установить обновление. Причина — в подробностях; текущая версия сохранена."
                    return
                }
                guard !result.target.isEmpty else { self.status.stringValue = "Обновление не найдено. Текущая версия сохранена."; return }
                self.cachedTarget = result.target
                self.updateButton.title = "Перезапустить"
                self.openUpdatedApp(result.target)
            }
            setBusy(true)
            status.stringValue = "Загружаем и проверяем обновление…"
        } catch { status.stringValue = "Не удалось начать обновление: \(error.localizedDescription)" }
    }
    private func openUpdatedApp(_ path: String) {
        guard !busy else { return }
        let target = URL(fileURLWithPath: path).standardizedFileURL
        guard target.pathExtension == "app", musicDirectory([target]) != nil,
              target != Bundle.main.bundleURL.standardizedFileURL else {
            status.stringValue = "Не удалось открыть обновление. Текущая версия доступна."
            return
        }
        openingUpdate = true
        setBusy(true)
        status.stringValue = "Открываем обновлённую версию…"
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--folder", folders.stringValue, "--recursive=\(recursive.state == .on)"]
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.openingUpdate = false
                if let error {
                    self.setBusy(false)
                    self.status.stringValue = "Не удалось открыть обновление: \(error.localizedDescription)"
                } else { NSApp.terminate(nil) }
            }
        }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard !busy, let folder = musicDirectory(filenames.map { URL(fileURLWithPath: $0) }) else { sender.reply(toOpenOrPrint: .failure); return }
        if window == nil { pendingFolder = folder } else { select(folder); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        sender.reply(toOpenOrPrint: .success)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
        if let checkProcess, checkProcess.isRunning { checkProcess.interrupt() }
        checkCleanup.wait()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !openingUpdate else { return .terminateCancel }
        guard busy else { return .terminateNow }
        if quitAfterStop { return .terminateLater }
        let alert = NSAlert()
        alert.messageText = updateProcess == nil ? "Остановить проверку и закрыть программу?" : "Отменить обновление и закрыть программу?"
        alert.informativeText = updateProcess == nil ? "Результаты уже проверенных записей сохранятся. При следующем запуске проверка продолжится." : "Текущая версия останется доступной. Незавершённая загрузка не будет установлена."
        alert.addButton(withTitle: "Остановить и выйти")
        alert.addButton(withTitle: updateProcess == nil ? "Продолжить проверку" : "Продолжить обновление")
        if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        guard busy else { return .terminateNow }
        quitAfterStop = true
        cancel()
        return .terminateLater
    }
}

if CommandLine.arguments.contains("--self-test") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("music-check-ui-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("трек.mp3")
    try Data([1]).write(to: file)
    precondition(musicDirectory([root]) == root.standardizedFileURL)
    precondition(musicDirectory([file]) == nil && musicDirectory([]) == nil && musicDirectory([root, root]) == nil)
    var parser = CheckProgressParser()
    precondition(parser.append(Data("[1/2] трек.mp3\n".utf8)).last?.percent == nil)
    let progressLine = Data("[Отчёт 17%] Фрагменты: 2 из 10. трек.mp3 — создание\n".utf8)
    precondition(parser.append(progressLine.prefix(5)).isEmpty)
    let progressUpdate = parser.append(progressLine.dropFirst(5))
    precondition(progressUpdate.last?.percent == 17 && progressUpdate.last?.message.contains("трек.mp3") == true)
    precondition(parser.append(Data("[2/2] другой.mp3\n".utf8)).isEmpty)
    precondition(parser.append(Data("[Отчёт 12%] старая строка\n".utf8)).last?.percent == 17)
    precondition(parser.append(Data("[Отчёт 101%] неверно\n".utf8)).isEmpty)
    precondition(parser.append(Data("[Отчёт 100%] Отчёт сохранён".utf8)).isEmpty)
    precondition(parser.append(Data(), finished: true).last?.percent == 100)
    let logURL = root.appendingPathComponent("logs/last-check.log")
    let writer = try CheckLogWriter(url: logURL)
    try writer.append(Data(repeating: 65, count: CheckLogWriter.limit - 10))
    let lastMessage = Data("\nПоследняя ошибка\n".utf8)
    try writer.append(Data(repeating: 66, count: CheckLogWriter.limit * 3 / 4))
    try writer.append(lastMessage)
    try writer.close()
    let savedLog = try Data(contentsOf: logURL)
    precondition(savedLog.count <= CheckLogWriter.limit && savedLog.suffix(lastMessage.count) == lastMessage)
    let linked = root.appendingPathComponent("original.txt")
    try Data("original".utf8).write(to: linked)
    try FileManager.default.removeItem(at: logURL)
    try FileManager.default.linkItem(at: linked, to: logURL)
    let replacement = try CheckLogWriter(url: logURL)
    try replacement.append(Data("new log".utf8))
    try replacement.close()
    let originalData = try Data(contentsOf: linked)
    precondition(originalData == Data("original".utf8))
    let result = try JSONDecoder().decode(CheckResult.self, from: Data("{\"output\":\"/tmp/Отчёт.html\",\"total\":3,\"checked\":2,\"fresh\":1,\"cached\":1,\"errors\":0,\"warnings\":0,\"incomplete\":1,\"interrupted\":true,\"error\":\"\"}".utf8))
    precondition(result.message.contains("Остановлено") && result.message.contains("2 из 3"))
    let reportStopped = try JSONDecoder().decode(CheckResult.self, from: Data("{\"output\":\"/tmp/report.html\",\"total\":3,\"checked\":3,\"fresh\":1,\"cached\":2,\"errors\":1,\"warnings\":0,\"incomplete\":0,\"interrupted\":true,\"report_interrupted\":true,\"error\":\"\"}".utf8))
    precondition(reportStopped.message.contains("Подготовка фрагментов остановлена"))
    let earlyStop = CheckResult(output: "", total: 0, checked: 0, fresh: 0, cached: 0, errors: 0, warnings: 0, incomplete: 0, interrupted: true, error: "проверка инструментов: signal: killed")
    precondition(earlyStop.message == "Проверка остановлена. Можно запустить её снова.")
    let denied = CheckResult(output: "", total: 0, checked: 0, fresh: 0, cached: 0, errors: 0, warnings: 0, incomplete: 0, interrupted: false, error: "open /test: operation not permitted")
    precondition(denied.message.contains("Нажмите «Выбрать…»"))
    let update = try JSONDecoder().decode(UpdateStatus.self, from: Data("{\"current\":\"1.0.0\",\"latest\":\"1.1.0\",\"available\":true,\"notes\":\"Исправления\",\"error\":\"\",\"target\":\"\"}".utf8))
    precondition(update.available && versionBanner(update, fallback: "1.0.0").contains("1.1.0"))
    let ordinary = try JSONDecoder().decode(UpdateStatus.self, from: Data("{\"current\":\"1.0.0\",\"latest\":\"1.1.0\",\"available\":true,\"notes\":\"Fix\",\"error\":\"\"}".utf8))
    precondition(ordinary.available && ordinary.target.isEmpty)
    let cached = try JSONDecoder().decode(UpdateStatus.self, from: Data("{\"current\":\"1.0.0\",\"target\":\"/tmp/New.app\"}".utf8))
    precondition(cached.target == "/tmp/New.app" && versionBanner(cached, fallback: "1.0.0").contains("готово"))
    let offline = UpdateStatus(current: "1.0.0", latest: "", available: false, notes: "", error: "offline", target: "")
    precondition(versionBanner(offline, fallback: "1.0.0").contains("Не удалось"))
    let installed = try JSONDecoder().decode(UpdateInstallResult.self, from: Data("{\"target\":\"/tmp/Music-check.app\",\"error\":\"\"}".utf8))
    precondition(installed.target.hasSuffix(".app") && installed.error.isEmpty)
    if let path = Bundle.main.url(forResource: "brand", withExtension: "png"), let image = NSImage(contentsOf: path), let rep = image.representations.first {
        precondition(rep.pixelsWide == 192*15 && rep.pixelsHigh == 169*9)
    }
    print("PASS: выбор одной папки, отклонение файлов, JSON и сообщение об остановке, online/offline/cached обновления, проценты отчёта и ограниченный журнал.")
} else {
    let app = NSApplication.shared
    let delegate = CheckApp()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
