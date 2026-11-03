import SwiftUI

struct SettingsView: View {
    @Bindable var store: CursorStore
    @State private var fill = Color.clear
    @State private var outline = Color.clear
    private var updates: UpdateService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            CursorModePicker(store: store)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CursorSourceEditor(profile: $store.profile)
                    CursorPreview(profile: store.profile)
                    controls
                    Divider()
                    ClickIndicatorSettingsView(store: .shared)
                    footer
                }
                .padding(.trailing, 2)
            }
        }
        .padding(24)
        .frame(width: 480, height: 720)
        .tint(.orange)
        .onAppear { syncColors() }
        .onChange(of: store.profile.fill) { syncColors() }
        .onChange(of: store.profile.outline) { syncColors() }
        .onChange(of: fill) { store.profile.fill = CursorColor(fill) }
        .onChange(of: outline) { store.profile.outline = CursorColor(outline) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("A cursor of your own.").font(.title2).bold()
                Text("Switch from the menu bar, anytime.").foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            LoginItemSettings()
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            CursorSizeControl(size: $store.profile.size)
            if store.profile.kind == .shape || store.profile.kind == .symbol {
                HStack {
                    Text("Fill")
                    Spacer()
                    ColorPicker("Fill", selection: $fill, supportsOpacity: false).labelsHidden()
                }
            }
            if store.profile.kind == .shape {
                HStack {
                    Text("Outline")
                    Spacer()
                    ColorPicker("Outline", selection: $outline, supportsOpacity: false).labelsHidden()
                }
            }
            HStack {
                Text("Click point")
                Spacer()
                Picker("Click point", selection: $store.profile.hotspot) {
                    ForEach(CursorHotspot.allCases) { hotspot in Text(hotspot.title).tag(hotspot) }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            VStack(alignment: .leading, spacing: 5) {
                Toggle("Preserve contextual cursors", isOn: $store.profile.preservesContextualCursors)
                Text("Experimental. Use macOS cursors for links, text, resizing, and dragging.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = store.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if store.contextualCursorUnavailable {
                Text("Cursor detection is unavailable. Your macOS pointer is active; turn off Preserve contextual cursors to use your custom cursor.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(store.isCustom ? (store.profile.preservesContextualCursors
                 ? "Changes apply as you edit. Contextual cursors keep their macOS appearance."
                 : "Changes apply as you edit. Your cursor keeps the same appearance over text and links.")
                 : "Your macOS pointer is active. Select Custom to use the previewed cursor.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Label("⌃⌥⌘C to switch", systemImage: "keyboard")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Style") { store.resetProfile() }
            }
            if !store.shortcutAvailable {
                Text("The shortcut is in use by another app. You can still switch from the menu bar.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if updates.isConfigured {
                Divider()
                HStack {
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(updates.availableVersion == nil ? "Check for Updates…" : "Update Available…") {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheckForUpdates)
                }
                .font(.callout)
            }
        }
    }

    private func syncColors() {
        if CursorColor(fill) != store.profile.fill { fill = store.profile.fill.color }
        if CursorColor(outline) != store.profile.outline { outline = store.profile.outline.color }
    }
}
