import AppKit
import Carbon.HIToolbox
import SwiftUI
import VeilCore

@MainActor
final class AppState: ObservableObject {
    @Published var status = "Ready"
    @Published var modelLoaded = false
    @Published var twins: [TwinMap.Entry] = []
    @Published var lastSpans: [Span] = []
    @Published var profileId: String = TwinPersona.alexRivera.id
    @Published var persona: TwinPersona = .alexRivera

    let cloaker = Cloaker(map: TwinMap(persona: .alexRivera))
    private let hotkeys = HotKeyManager()

    init() {
        loadModel()
        // ⌃⌥⌘C cloak, ⌃⌥⌘U uncloak, ⌃⌥⌘K clear session
        let mods = controlKey | optionKey | cmdKey
        hotkeys.register(id: 1, keyCode: kVK_ANSI_C, modifiers: mods) { [weak self] in Task { @MainActor in await self?.cloakClipboard() } }
        hotkeys.register(id: 2, keyCode: kVK_ANSI_U, modifiers: mods) { [weak self] in Task { @MainActor in self?.uncloakClipboard() } }
        hotkeys.register(id: 3, keyCode: kVK_ANSI_K, modifiers: mods) { [weak self] in Task { @MainActor in self?.clearSession() } }
    }

    func loadModel() {
        guard let dir = ModelLocator.find() else {
            status = "Model missing — run scripts/download-model.sh (regex-only mode)"; return
        }
        do { cloaker.ner = try RampartONNXDetector(modelDir: dir); modelLoaded = true; status = "Rampart loaded" }
        catch { status = "Model load failed: \(error.localizedDescription) (regex-only)" }
    }

    func cloakClipboard() async {
        guard let text = Clipboard.read(), !text.isEmpty else { status = "Clipboard empty"; return }
        do {
            let r = try await cloaker.cloak(text)
            Clipboard.write(r.text)
            lastSpans = r.spans; twins = cloaker.map.entries
            status = "Cloaked \(r.replaced) item\(r.replaced == 1 ? "" : "s")"
        } catch { status = "Cloak failed: \(error.localizedDescription)" }
    }

    func uncloakClipboard() {
        guard let text = Clipboard.read() else { status = "Clipboard empty"; return }
        let restored = cloaker.uncloak(text)
        Clipboard.write(restored)
        status = restored == text ? "Nothing to restore" : "Uncloaked clipboard"
    }

    /// Clear the session. Random mode re-rolls the persona; presets keep theirs.
    func clearSession() {
        let p = makePersona(profileId)
        cloaker.map.clear(persona: p); persona = p; twins = []; lastSpans = []
        status = p.isRandom ? "Session cleared — new random persona \(p.fullName)" : "Session cleared"
    }

    /// Switching profile starts a fresh session (old twins would no longer be coherent).
    func selectProfile(_ id: String) {
        guard id != profileId else { return }
        profileId = id; clearSession()
        status = "Profile: \(persona.profileName) (\(persona.fullName)) — session cleared"
    }

    private func makePersona(_ id: String) -> TwinPersona {
        TwinPersona.presets.first { $0.id == id } ?? .random(seed: UInt64.random(in: .min ... .max))
    }
}

enum Clipboard {
    static func read() -> String? { NSPasteboard.general.string(forType: .string) }
    static func write(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        // Hint to clipboard managers not to persist this item.
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    }
}
