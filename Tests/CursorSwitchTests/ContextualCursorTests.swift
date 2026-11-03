import AppKit
import Testing
@testable import CursorSwitch

@MainActor
struct ContextualCursorTests {
    private func withStore(_ body: (CursorStore, ContextVisibility, ContextRenderer, ContextMonitor) throws -> Void) rethrows {
        let suite = "ContextualCursorTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = ContextVisibility()
        let renderer = ContextRenderer()
        let monitor = ContextMonitor()
        let store = CursorStore(defaults: defaults, visibility: visibility, renderer: renderer, systemCursorMonitor: monitor)
        defer { store.selectDefault() }
        try body(store, visibility, renderer, monitor)
    }

    @Test func contextualCursorsYieldAndReturnWithoutAccumulatingHides() {
        withStore { store, visibility, renderer, monitor in
            store.profile.preservesContextualCursors = true
            store.selectCustom()
            #expect(visibility.hidden)
            monitor.send(.contextual)
            #expect(store.isCustom && store.isShowingSystemCursor)
            #expect(!visibility.hidden && !renderer.visible)
            monitor.send(.contextual)
            monitor.send(.arrow)
            #expect(visibility.hidden && renderer.visible)
            #expect(visibility.hides == 2)
            monitor.send(.arrow)
            #expect(visibility.hides == 2)
        }
    }

    @Test func disabledPreferenceDoesNotMonitorAndDisablingRestoresCustom() {
        withStore { store, visibility, renderer, monitor in
            store.selectCustom()
            #expect(monitor.handler == nil)
            store.profile.preservesContextualCursors = true
            monitor.send(.contextual)
            store.profile.preservesContextualCursors = false
            #expect(monitor.handler == nil)
            #expect(visibility.hidden && renderer.visible)
            #expect(!store.isShowingSystemCursor)
        }
    }

    @Test func unavailableLookupKeepsNativeVisibleAndRecovers() {
        withStore { store, visibility, renderer, monitor in
            store.profile.preservesContextualCursors = true
            store.selectCustom()
            monitor.send(.unavailable)
            #expect(store.contextualCursorUnavailable)
            #expect(!visibility.hidden && !renderer.visible)
            store.profile.size = 120
            #expect(!renderer.visible)
            monitor.send(.arrow)
            #expect(!store.contextualCursorUnavailable)
            #expect(visibility.hidden && renderer.visible)
            #expect(renderer.profile?.size == 120)
        }
    }

    @Test func switchingToDefaultRejectsQueuedMonitorCallbacks() {
        withStore { store, visibility, renderer, monitor in
            store.profile.preservesContextualCursors = true
            store.selectCustom()
            let callback = monitor.handler
            store.selectDefault()
            callback?(.contextual)
            callback?(.arrow)
            #expect(!store.isCustom && !visibility.hidden && !renderer.visible)
            #expect(monitor.handler == nil)
        }
    }

    @Test func failedReturnToCustomRestoresNativeAndStopsMonitoring() {
        withStore { store, visibility, renderer, monitor in
            store.profile.preservesContextualCursors = true
            store.selectCustom()
            monitor.send(.contextual)
            visibility.shouldFail = true
            monitor.send(.arrow)
            #expect(!store.isCustom && !visibility.hidden && !renderer.visible)
            #expect(store.errorMessage != nil)
            #expect(monitor.handler == nil)
        }
    }

    @Test func classifiesArtworkRatherThanCursorObjectIdentity() {
        _ = NSApplication.shared
        let arrow = NSCursor.arrow
        let copy = NSCursor(image: arrow.image, hotSpot: arrow.hotSpot)
        #expect(SystemCursorMonitor.classify(copy, arrow: arrow) == .arrow)
        for cursor in [NSCursor.iBeam, .pointingHand, .openHand, .closedHand] {
            #expect(SystemCursorMonitor.classify(cursor, arrow: arrow) == .contextual)
        }
        #expect(SystemCursorMonitor.classify(nil, arrow: arrow) == .unavailable)
    }

    @Test func olderProfilesKeepExperimentDisabled() throws {
        let profile = try JSONDecoder().decode(CursorProfile.self, from: Data("{}".utf8))
        #expect(!profile.preservesContextualCursors)
        var changed = profile
        changed.preservesContextualCursors = true
        let restored = try JSONDecoder().decode(CursorProfile.self, from: JSONEncoder().encode(changed))
        #expect(restored.preservesContextualCursors)
    }
}

@MainActor
private final class ContextMonitor: SystemCursorMonitoring {
    var handler: (@MainActor (SystemCursorState) -> Void)?
    func start(handler: @escaping @MainActor (SystemCursorState) -> Void) { self.handler = handler }
    func stop() { handler = nil }
    func send(_ state: SystemCursorState) { handler?(state) }
}

@MainActor
private final class ContextVisibility: CursorVisibility {
    var hidden = false
    var hides = 0
    var shouldFail = false
    func hide() throws {
        if shouldFail { throw CursorFailure.cannotHide }
        hides += 1
        hidden = true
    }
    func restore() { hidden = false }
}

@MainActor
private final class ContextRenderer: CursorRendering {
    var visible = false
    var profile: CursorProfile?
    func show(profile: CursorProfile) { self.profile = profile; visible = true }
    func update(profile: CursorProfile) { self.profile = profile }
    func dismiss() { visible = false }
}
