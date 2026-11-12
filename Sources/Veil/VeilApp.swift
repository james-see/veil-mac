import AppKit
import SwiftUI
import VeilCore

@main
struct VeilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(state)
        } label: {
            Image(systemName: state.twins.isEmpty ? "theatermasks" : "theatermasks.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // No Dock icon when run via `swift run` (the .app sets LSUIElement in Info.plist).
    func applicationDidFinishLaunching(_ n: Notification) { NSApp.setActivationPolicy(.accessory) }
}

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @State private var showMap = false
    @State private var showPersona = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Veil").font(.headline)
                Spacer()
                Circle().fill(state.modelLoaded ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(state.modelLoaded ? "Rampart" : "Regex only").font(.caption).foregroundStyle(.secondary)
            }
            Text(state.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Divider()
            HStack {
                Image(systemName: state.persona.isRandom ? "dice" : "person.crop.circle")
                Picker("Profile", selection: Binding(get: { state.profileId }, set: { state.selectProfile($0) })) {
                    ForEach(TwinPersona.presets) { Text($0.profileName).tag($0.id) }
                    Text("Random").tag(TwinPersona.randomId)
                }.labelsHidden()
                if state.persona.isRandom {
                    Button { state.clearSession() } label: { Image(systemName: "arrow.clockwise") }.help("Re-roll (clears session)")
                }
            }
            DisclosureGroup("Active: \(state.persona.profileName) — \(state.persona.fullName)", isExpanded: $showPersona) {
                VStack(alignment: .leading, spacing: 2) {
                    field("Name", state.persona.fullName)
                    field("Email", state.persona.email)
                    field("Phone", state.persona.phone)
                    field("Address", "\(state.persona.street), \(state.persona.city), \(state.persona.state)")
                }
            }.font(.caption)
            Divider()
            Button { Task { await state.cloakClipboard() } } label: { row("Cloak Clipboard", "⌃⌥⌘C", "eye.slash") }
            Button { state.uncloakClipboard() } label: { row("Uncloak Clipboard", "⌃⌥⌘U", "eye") }
            Button(role: .destructive) { state.clearSession() } label: { row("Clear Session", "⌃⌥⌘K", "trash") }
            Divider()
            DisclosureGroup("Session twins (\(state.twins.count))", isExpanded: $showMap) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(state.twins, id: \.twin) { e in
                            HStack {
                                Text(e.label.rawValue).font(.caption2.monospaced()).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                Text(e.original).font(.caption).lineLimit(1)
                                Image(systemName: "arrow.right").font(.caption2)
                                Text(e.twin).font(.caption).lineLimit(1)
                            }
                        }
                    }
                }.frame(maxHeight: 160)
            }
            Divider()
            Button("Quit Veil") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(width: 340)
    }

    private func field(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary).frame(width: 56, alignment: .leading); Text(v).textSelection(.enabled).lineLimit(1) }
            .font(.caption)
    }

    private func row(_ title: String, _ key: String, _ icon: String) -> some View {
        HStack { Image(systemName: icon).frame(width: 18); Text(title); Spacer(); Text(key).foregroundStyle(.secondary).font(.caption) }
            .contentShape(Rectangle())
    }
}
