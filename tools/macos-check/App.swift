import AppKit

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
    var message: String {
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
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.backgroundColor = ink.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:)") }
    private func folder(_ sender: NSDraggingInfo) -> URL? {
        guard available?() == true else { return nil }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return musicDirectory(urls)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { folder(sender) == nil ? [] : .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
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
            if elapsed >= 4.5 { self.reset(); return }
            self.frameIndex = min(134, Int(elapsed * 30))
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


final class CheckApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let folders = FolderBox(frame: NSRect(x: 28, y: 434, width: 486, height: 28))
    private let recursive = NSButton(checkboxWithTitle: "Включая подпапки", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "Выберите папку и нажмите «Проверить».")
    private let progress = NSProgressIndicator(frame: NSRect(x: 28, y: 320, width: 604, height: 12))
    private let log = NSTextView()
    private let scroll = NSScrollView(frame: NSRect(x: 28, y: 112, width: 604, height: 170))
    private var browse: NSButton!
    private var start: NSButton!
    private var stop: NSButton!
    private var report: NSButton!
    private var process: Process?
    private var reportURL: URL?
    private var pendingFolder: URL?
    private var quitAfterStop = false
    private var logBytes = Data()
    private var versionLabel: NSTextField!
    private var updateBanner: NSView!
    private var updateButton: NSButton!
    private var checkProcess: Process?
    private var updateProcess: Process?
    private var updateAvailable = false
    private var cachedTarget = ""
    private var openingUpdate = false
    private var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1" }
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
        _ = label("Оригиналы не меняются. Перетащите папку или выберите из шести последних.", frame: NSRect(x: 28, y: 477, width: 604, height: 22), size: 12, color: muted)
        folders.isEditable = true
        folders.completes = false
        folders.numberOfVisibleItems = 6
        folders.setAccessibilityLabel("Папка с музыкой")
        folders.registerForDraggedTypes([.fileURL])
        folders.canDrop = { [weak self] in self?.busy == false }
        folders.accept = { [weak self] in self?.select($0) }
        root.addSubview(folders)
        refreshFolders()
        browse = button("Выбрать…", frame: NSRect(x: 526, y: 432, width: 106, height: 32), action: #selector(choose))
        recursive.frame = NSRect(x: 28, y: 395, width: 300, height: 24)
        recursive.state = .on
        root.addSubview(recursive)
        status.frame = NSRect(x: 28, y: 342, width: 604, height: 46)
        status.font = .systemFont(ofSize: 14)
        status.textColor = .white
        root.addSubview(status)
        progress.style = .bar
        progress.isIndeterminate = true
        progress.isDisplayedWhenStopped = false
        root.addSubview(progress)
        let details = NSButton(checkboxWithTitle: "Показать технические подробности", target: self, action: #selector(toggleDetails(_:)))
        details.frame = NSRect(x: 28, y: 288, width: 440, height: 24)
        root.addSubview(details)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.isHidden = true
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
        scroll.documentView = log
        root.addSubview(scroll)
        root.addSubview(BrandView(frame: NSRect(x: 28, y: 22, width: 112, height: 62), resource: Bundle.main.url(forResource: "brand", withExtension: "png")))
        report = button("Открыть отчёт", frame: NSRect(x: 202, y: 38, width: 160, height: 32), action: #selector(openReport))
        report.isEnabled = false
        stop = button("Остановить", frame: NSRect(x: 366, y: 38, width: 116, height: 32), action: #selector(cancel))
        stop.isEnabled = false
        start = button("Проверить", frame: NSRect(x: 490, y: 38, width: 142, height: 32), action: #selector(check))
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
        checkForUpdates()
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
    private func select(_ folder: URL) {
        guard !busy else { return }
        folders.stringValue = folder.path
        status.stringValue = "Папка выбрана. Нажмите «Проверить»."
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
    @objc private func toggleDetails(_ sender: NSButton) { scroll.isHidden = sender.state != .on }
    @objc private func check() {
        guard !busy else { return }
        let path = (folders.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !path.isEmpty, let folder = musicDirectory([URL(fileURLWithPath: path)]) else {
            status.stringValue = "Выберите существующую папку с музыкой."
            return
        }
        guard let resources = Bundle.main.resourceURL, let executable = Bundle.main.executableURL else { return }
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
        logBytes.removeAll()
        log.string = ""
        reportURL = nil
        report.isEnabled = false
        do { try task.run() }
        catch {
            try? FileManager.default.removeItem(at: temp)
            status.stringValue = "Не удалось запустить проверку. Причина — в подробностях."
            appendLog(Data("\(error)\n".utf8))
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
                DispatchQueue.main.async { [weak self] in self?.appendLog(data) }
            }
            task.waitUntilExit()
            let result = (try? Data(contentsOf: resultURL)).flatMap { try? JSONDecoder().decode(CheckResult.self, from: $0) }
            try? FileManager.default.removeItem(at: temp)
            DispatchQueue.main.async { [weak self] in self?.finished(result) }
        }
    }
    private func appendLog(_ data: Data) {
        logBytes.append(data)
        if logBytes.count > 262_144 { logBytes.removeFirst(logBytes.count - 262_144) }
        log.string = String(decoding: logBytes, as: UTF8.self)
        log.scrollToEndOfDocument(nil)
        if busy && stop.isEnabled {
            let lines = log.string.components(separatedBy: "\n")
            if let line = lines.last(where: { $0.hasPrefix("[") }), let end = line.firstIndex(of: "]") {
                let counts = line[line.index(after: line.startIndex)..<end].split(separator: "/")
                if counts.count == 2, let current = Int(counts[0]), let total = Int(counts[1]), total > 0 {
                    status.stringValue = "Проверяем запись \(current) из \(total). Неизменившиеся записи берём из истории."
                }
            }
            if lines.last(where: { !$0.isEmpty })?.hasPrefix("Подготовка встроенных фрагментов") == true {
                status.stringValue = "Готовим отчёт и короткие фрагменты для прослушивания…"
            }
        }
    }
    private func setBusy(_ value: Bool) {
        folders.isEnabled = !value
        recursive.isEnabled = !value
        browse.isEnabled = !value
        start.isEnabled = !value
        stop.isEnabled = value && (process != nil || updateProcess != nil)
        report.isEnabled = !value && reportURL != nil
        updateButton.isEnabled = !value && updateAvailable
        if value { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
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
    // The updater runs separately from music checking. Checking availability
    // never blocks the window, and installation cannot start while music is busy.
    private func launchUpdateCommand(_ mode: String, completion: @escaping (Data?, Int32) -> Void) throws -> Process {
        guard let executable = Bundle.main.executableURL else {
            throw NSError(domain: "IGUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не найден движок обновления."])
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ig-update-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let resultURL = temporary.appendingPathComponent("result.json")
        let task = Process()
        task.executableURL = executable.deletingLastPathComponent().appendingPathComponent("music-check-engine")
        task.arguments = [mode, "--result", resultURL.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do { try task.run() }
        catch { try? FileManager.default.removeItem(at: temporary); throw error }
        DispatchQueue.global(qos: .utility).async {
            task.waitUntilExit()
            let data = try? Data(contentsOf: resultURL)
            try? FileManager.default.removeItem(at: temporary)
            DispatchQueue.main.async { completion(data, task.terminationStatus) }
        }
        return task
    }
    private func checkForUpdates() {
        do {
            checkProcess = try launchUpdateCommand("--update-status") { [weak self] data, _ in
                guard let self else { return }
                self.checkProcess = nil
                guard let data, let update = try? JSONDecoder().decode(UpdateStatus.self, from: data) else {
                    self.versionLabel.stringValue = "Версия \(self.currentVersion) · Не удалось проверить обновления"
                    return
                }
                self.versionLabel.stringValue = versionBanner(update, fallback: self.currentVersion)
                self.versionLabel.toolTip = update.error.isEmpty ? update.notes : update.error
                self.cachedTarget = update.target
                self.updateAvailable = update.available || !update.target.isEmpty
                self.updateBanner.isHidden = !self.updateAvailable
                self.versionLabel.textColor = self.updateAvailable ? mint : muted
                self.updateButton.isHidden = !self.updateAvailable
                self.updateButton.isEnabled = self.updateAvailable && !self.busy
                self.updateButton.title = update.target.isEmpty ? "Обновить" : "Перезапустить"
                if !update.target.isEmpty && !self.busy { self.openUpdatedApp(update.target) }
            }
        } catch { versionLabel.stringValue = "Версия \(currentVersion) · Не удалось проверить обновления" }
    }
    @objc private func installUpdate() {
        guard !busy, updateAvailable else { return }
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
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !openingUpdate else { return .terminateCancel }
        guard busy else {
            if let checkProcess, checkProcess.isRunning { checkProcess.interrupt(); checkProcess.waitUntilExit() }
            return .terminateNow
        }
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
    let result = try JSONDecoder().decode(CheckResult.self, from: Data("{\"output\":\"/tmp/Отчёт.html\",\"total\":3,\"checked\":2,\"fresh\":1,\"cached\":1,\"errors\":0,\"warnings\":0,\"incomplete\":1,\"interrupted\":true,\"error\":\"\"}".utf8))
    precondition(result.message.contains("Остановлено") && result.message.contains("2 из 3"))
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
    print("PASS: выбор одной папки, отклонение файлов, JSON и сообщение об остановке, online/offline/cached обновления.")
} else {
    let app = NSApplication.shared
    let delegate = CheckApp()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
