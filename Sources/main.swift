// Select2Admin pour macOS
// Portage de Select2Search (AutoIt, Windows) : sélectionner un identifiant d'armoire
// n'importe où, appuyer deux fois sur la touche de déclenchement (⌘ droite par défaut),
// et la page d'administration Zeendoc correspondante s'ouvre dans le navigateur.

import AppKit
import ApplicationServices
import Carbon
import ServiceManagement

// MARK: - Configuration (config.ini, même format que la version Windows)

struct Classeur {
    let name: String
    let url: String
}

final class Config {
    static let placeholder = "{Selected_Text}"
    static let defaultContent = """
    ; Select2Admin — configuration
    ; Chaque ligne de [Classeurs] : Nom = "URL contenant {Selected_Text}"
    ; Une seule ligne : l'URL s'ouvre directement. Plusieurs : un menu permet de choisir.
    [Classeurs]
    Admin armoire = "https://admin.zeendoc.com/Admin_Armoires/Armoire.php?Popup=ok&N_Client={Selected_Text}"

    [delay]
    ; Attente maximale (ms) de la copie de la sélection
    delay = "100"

    """

    private(set) var classeurs: [Classeur] = []
    private(set) var delayMs: Int = 100
    private(set) var fileURL: URL

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Select2Admin", isDirectory: true)
    }

    init() {
        fileURL = Config.locate()
        reload()
    }

    /// 1. config.ini placé à côté de l'app (comme sous Windows)
    /// 2. ~/Library/Application Support/Select2Admin/config.ini (créé au premier lancement)
    static func locate() -> URL {
        let fm = FileManager.default
        let besideApp = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("config.ini")
        if fm.fileExists(atPath: besideApp.path) { return besideApp }

        let user = supportDir.appendingPathComponent("config.ini")
        if !fm.fileExists(atPath: user.path) {
            try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
            if let bundled = Bundle.main.url(forResource: "config", withExtension: "ini") {
                try? fm.copyItem(at: bundled, to: user)
            } else {
                try? defaultContent.write(to: user, atomically: true, encoding: .utf8)
            }
        }
        return user
    }

    func reload() {
        fileURL = Config.locate()
        var text = ""
        if let data = try? Data(contentsOf: fileURL) {
            text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
        }
        let sections = Config.parse(text)
        classeurs = (sections["classeurs"] ?? [])
            .filter { !$0.value.isEmpty }
            .map { Classeur(name: $0.key, url: $0.value) }
        if let d = sections["delay"]?.first(where: { $0.key.lowercased() == "delay" }),
           let v = Int(d.value) {
            delayMs = max(20, v)
        }
    }

    static func parse(_ text: String) -> [String: [(key: String, value: String)]] {
        var result: [String: [(key: String, value: String)]] = [:]
        var current = ""
        let clean = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        for raw in clean.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                current = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            result[current, default: []].append((key: key, value: value))
        }
        return result
    }
}

// MARK: - Touche de déclenchement (double appui sur une touche de modification seule)

enum TriggerKey: String, CaseIterable {
    case rightCommand, rightOption, rightControl, rightShift

    var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .rightOption: return 61
        case .rightControl: return 62
        case .rightShift: return 60
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand: return .command
        case .rightOption: return .option
        case .rightControl: return .control
        case .rightShift: return .shift
        }
    }

    var label: String {
        switch self {
        case .rightCommand: return "⌘ Commande droite"
        case .rightOption: return "⌥ Option droite"
        case .rightControl: return "⌃ Contrôle droite"
        case .rightShift: return "⇧ Maj droite"
        }
    }

    var short: String {
        switch self {
        case .rightCommand: return "⌘ droite"
        case .rightOption: return "⌥ droite"
        case .rightControl: return "⌃ droite"
        case .rightShift: return "⇧ droite"
        }
    }
}

final class DoubleTapMonitor {
    var key: TriggerKey
    /// Délai max entre les deux appuis (≈ 3 × 150 ms dans la version Windows)
    var interval: TimeInterval = 0.45
    let onTrigger: () -> Void

    private var monitors: [Any] = []
    private var isDown = false
    private var dirty = false
    private var lastTap: TimeInterval = 0

    init(key: TriggerKey, onTrigger: @escaping () -> Void) {
        self.key = key
        self.onTrigger = onTrigger
    }

    func start() {
        stop()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in self?.handleFlags(e) }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in self?.handleKeyDown() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in self?.handleFlags(e); return e }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in self?.handleKeyDown(); return e }) {
            monitors.append(m)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        isDown = false
        dirty = false
        lastTap = 0
    }

    private func handleFlags(_ e: NSEvent) {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        if e.keyCode == key.keyCode {
            if !isDown {
                isDown = true
                // Une autre touche de modification déjà enfoncée : ce n'est pas un appui « seul »
                dirty = !mods.subtracting(key.flag).isEmpty
            } else {
                isDown = false
                if dirty { lastTap = 0; return }
                let now = ProcessInfo.processInfo.systemUptime
                if lastTap > 0, now - lastTap <= interval {
                    lastTap = 0
                    onTrigger()
                } else {
                    lastTap = now
                }
            }
        } else {
            // Autre touche de modification : annule la séquence en cours
            if isDown { dirty = true }
            lastTap = 0
        }
    }

    private func handleKeyDown() {
        // Une lettre tapée pendant ou entre les appuis (ex. ⌘C) annule la séquence
        if isDown { dirty = true }
        lastTap = 0
    }
}

// MARK: - Récupération du texte sélectionné

enum SelectionGrabber {
    /// Simule ⌘C, lit le presse-papiers puis le restaure (comme la version Windows).
    /// Repli sur l'API d'accessibilité si l'application ne copie rien.
    static func grab(maxWaitMs: Int, completion: @escaping (String?) -> Void) {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        pb.clearContents()
        let startCount = pb.changeCount
        postCopyShortcut()

        let deadline = Date().addingTimeInterval(Double(max(maxWaitMs, 400)) / 1000)
        func poll() {
            if pb.changeCount != startCount {
                // laisser l'application finir d'écrire
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    let text = pb.string(forType: .string)
                    restore(saved, to: pb)
                    completion(text?.isEmpty == false ? text : axSelectedText())
                }
            } else if Date() > deadline {
                restore(saved, to: pb)
                completion(axSelectedText())
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
    }

    private static func snapshot(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pb: NSPasteboard) {
        pb.clearContents()
        if !items.isEmpty { pb.writeObjects(items) }
    }

    private static func postCopyShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let code = keyCode(for: "c")
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Code de touche produisant `char` dans la disposition clavier active (AZERTY, BÉPO, Dvorak…)
    private static func keyCode(for char: Character) -> CGKeyCode {
        let fallback: CGKeyCode = 8 // position de « C » en QWERTY/AZERTY
        guard let target = char.unicodeScalars.first?.value,
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return fallback }
        let layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> CGKeyCode in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return fallback }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, 4, &length, &chars)
                if status == noErr, length == 1, UInt32(chars[0]) == target { return CGKeyCode(code) }
            }
            return fallback
        }
    }

    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedRef as! AXUIElement
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success
        else { return nil }
        let text = selected as? String
        return text?.isEmpty == false ? text : nil
    }
}

// MARK: - Application (barre des menus)

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let config = Config()
    private var statusItem: NSStatusItem!
    private var monitor: DoubleTapMonitor!
    private var trustTimer: Timer?
    private var busy = false

    private static let triggerDefaultsKey = "triggerKey"

    private var triggerKey: TriggerKey {
        get { TriggerKey(rawValue: UserDefaults.standard.string(forKey: Self.triggerDefaultsKey) ?? "") ?? .rightCommand }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.triggerDefaultsKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        monitor = DoubleTapMonitor(key: triggerKey) { [weak self] in self?.triggered() }

        if AXIsProcessTrusted() {
            monitor.start()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            waitForAccessibility()
        }
    }

    // Les moniteurs globaux ne fonctionnent qu'une fois l'accès Accessibilité accordé
    private func waitForAccessibility() {
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.monitor.start()
            self?.setIcon()
        }
        setIcon()
    }

    private func setIcon(highlight: Bool = false) {
        guard let button = statusItem.button else { return }
        let symbol = highlight ? "archivebox.fill" : (AXIsProcessTrusted() ? "archivebox" : "exclamationmark.triangle")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Select2Admin")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Zeendoc Select2Admin — double \(triggerKey.short)"
    }

    private func flashIcon() {
        setIcon(highlight: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.setIcon() }
    }

    // MARK: Déclenchement

    private func triggered() {
        guard !busy else { return }
        busy = true
        config.reload()
        SelectionGrabber.grab(maxWaitMs: config.delayMs) { [weak self] text in
            guard let self else { return }
            self.busy = false
            self.handle(text)
        }
    }

    private func handle(_ raw: String?) {
        let text = (raw ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty else { NSSound.beep(); return }

        let classeurs = config.classeurs
        switch classeurs.count {
        case 0:
            alert("Aucun classeur configuré",
                  "Ajoutez au moins une ligne dans la section [Classeurs] de :\n\(config.fileURL.path)")
        case 1:
            open(classeurs[0], with: text)
        default:
            chooseClasseur(classeurs, for: text)
        }
    }

    private func chooseClasseur(_ classeurs: [Classeur], for text: String) {
        let menu = NSMenu()
        let shown = text.count > 40 ? String(text.prefix(40)) + "…" : text
        let header = NSMenuItem(title: "Rechercher « \(shown) » dans :", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (i, c) in classeurs.enumerated() {
            let item = NSMenuItem(title: c.name, action: #selector(chooseItem(_:)),
                                  keyEquivalent: i < 9 ? String(i + 1) : "")
            item.keyEquivalentModifierMask = []
            item.target = self
            item.representedObject = (c, text)
            menu.addItem(item)
        }
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func chooseItem(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? (Classeur, String) else { return }
        open(pair.0, with: pair.1)
    }

    private func open(_ c: Classeur, with text: String) {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        let urlString = c.url.replacingOccurrences(of: Config.placeholder, with: encoded)
        guard let url = URL(string: urlString) else {
            alert("URL invalide", "Vérifiez l'entrée « \(c.name) » de config.ini :\n\(c.url)")
            return
        }
        flashIcon()
        NSWorkspace.shared.open(url)
    }

    // MARK: Menu de la barre des menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        config.reload()

        let title = NSMenuItem(title: "Select2Admin — double \(triggerKey.short)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if !AXIsProcessTrusted() {
            menu.addItem(item("⚠︎ Autoriser l'accessibilité…", #selector(openAccessibilitySettings)))
        }

        menu.addItem(item("Ouvrir une armoire…", #selector(manualEntry), key: "o"))
        menu.addItem(.separator())

        let keyMenu = NSMenu()
        for k in TriggerKey.allCases {
            let it = item(k.label, #selector(selectTrigger(_:)))
            it.representedObject = k.rawValue
            it.state = (k == triggerKey) ? .on : .off
            keyMenu.addItem(it)
        }
        let keyItem = NSMenuItem(title: "Touche de déclenchement", action: nil, keyEquivalent: "")
        keyItem.submenu = keyMenu
        menu.addItem(keyItem)

        let classeursMenu = NSMenu()
        if config.classeurs.isEmpty {
            let none = NSMenuItem(title: "Aucun", action: nil, keyEquivalent: "")
            none.isEnabled = false
            classeursMenu.addItem(none)
        }
        for c in config.classeurs {
            let it = NSMenuItem(title: c.name, action: nil, keyEquivalent: "")
            it.toolTip = c.url
            it.isEnabled = false
            classeursMenu.addItem(it)
        }
        classeursMenu.addItem(.separator())
        classeursMenu.addItem(item("Modifier config.ini…", #selector(editConfig)))
        classeursMenu.addItem(item("Afficher dans le Finder", #selector(revealConfig)))
        let classeursItem = NSMenuItem(title: "Classeurs (\(config.classeurs.count))", action: nil, keyEquivalent: "")
        classeursItem.submenu = classeursMenu
        menu.addItem(classeursItem)

        let login = item("Ouvrir à l'ouverture de session", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Quitter Select2Admin", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    @objc private func selectTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let k = TriggerKey(rawValue: raw) else { return }
        triggerKey = k
        monitor.key = k
        if AXIsProcessTrusted() { monitor.start() }
        setIcon()
    }

    @objc private func manualEntry() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Ouvrir une armoire"
        a.informativeText = "Identifiant de l'armoire :"
        a.addButton(withTitle: "Ouvrir")
        a.addButton(withTitle: "Annuler")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        if let clip = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty, clip.count <= 64, !clip.contains("\n") {
            field.stringValue = clip
        }
        a.accessoryView = field
        a.window.initialFirstResponder = field
        if a.runModal() == .alertFirstButtonReturn {
            config.reload()
            handle(field.stringValue)
        }
    }

    @objc private func editConfig() {
        NSWorkspace.shared.open([config.fileURL],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([config.fileURL])
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Ouverture à l'ouverture de session", error.localizedDescription)
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        waitForAccessibility()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }
}

// MARK: - Point d'entrée

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
