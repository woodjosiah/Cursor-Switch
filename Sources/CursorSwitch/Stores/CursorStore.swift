import AppKit
import Observation

@MainActor
@Observable
final class CursorStore {
    static let shared = CursorStore()
    static let profileKey = "customCursorProfile.v1"

    var profile: CursorProfile {
        didSet {
            let safe = profile.sanitized
            if safe != profile { profile = safe }
            if let data = try? JSONEncoder().encode(safe) { defaults.set(data, forKey: Self.profileKey) }
            if isCustom {
                if CursorArtwork.validationMessage(for: safe) == nil {
                    if !isShowingSystemCursor { renderer.update(profile: safe) }
                    configureContextualCursors()
                } else {
                    selectDefault()
                }
            }
        }
    }
    private(set) var isCustom = false
    var errorMessage: String?
    var shortcutAvailable = true
    private(set) var isShowingSystemCursor = false
    private(set) var contextualCursorUnavailable = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let visibility: any CursorVisibility
    @ObservationIgnored private let renderer: any CursorRendering
    @ObservationIgnored private let systemCursorMonitor: any SystemCursorMonitoring

    init(defaults: UserDefaults = .standard,
         visibility: (any CursorVisibility)? = nil,
         renderer: (any CursorRendering)? = nil,
         systemCursorMonitor: (any SystemCursorMonitoring)? = nil) {
        self.defaults = defaults
        self.visibility = visibility ?? NativeCursorVisibility()
        self.renderer = renderer ?? CursorOverlay()
        self.systemCursorMonitor = systemCursorMonitor ?? SystemCursorMonitor()
        if let data = defaults.data(forKey: Self.profileKey),
           let saved = try? JSONDecoder().decode(CursorProfile.self, from: data) {
            profile = saved.sanitized
        } else {
            profile = CursorProfile()
        }
        // Always launch in default mode, including after a forced quit.
    }

    func selectCustom() {
        guard !isCustom else { return }
        errorMessage = nil
        if let message = CursorArtwork.validationMessage(for: profile) {
            errorMessage = message
            return
        }
        renderer.show(profile: profile)
        do {
            try visibility.hide()
            isCustom = true
            configureContextualCursors()
        } catch {
            visibility.restore()
            renderer.dismiss()
            errorMessage = error.localizedDescription
        }
    }

    func selectDefault() {
        systemCursorMonitor.stop()
        visibility.restore()
        renderer.dismiss()
        isCustom = false
        isShowingSystemCursor = false
        contextualCursorUnavailable = false
        errorMessage = nil
    }

    func toggle() {
        if isCustom { selectDefault() } else { selectCustom() }
    }

    func resetProfile() { profile = CursorProfile() }

    private func configureContextualCursors() {
        systemCursorMonitor.stop()
        contextualCursorUnavailable = false
        guard profile.preservesContextualCursors else {
            if isShowingSystemCursor { applySystemCursorState(.arrow) }
            return
        }
        systemCursorMonitor.start { [weak self] state in
            guard let self, self.isCustom, self.profile.preservesContextualCursors else { return }
            self.applySystemCursorState(state)
        }
    }

    private func applySystemCursorState(_ state: SystemCursorState) {
        contextualCursorUnavailable = state == .unavailable
        let showSystem = state != .arrow
        guard showSystem != isShowingSystemCursor else { return }
        if showSystem {
            // Balance all hides and stop the visibility watchdog before yielding.
            visibility.restore()
            renderer.dismiss()
            isShowingSystemCursor = true
        } else {
            renderer.show(profile: profile)
            do {
                try visibility.hide()
                isShowingSystemCursor = false
            } catch {
                selectDefault()
                errorMessage = error.localizedDescription
            }
        }
    }
}
