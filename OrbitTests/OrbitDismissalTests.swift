import Testing
@testable import Orbit

struct OrbitDismissalTests {
    @Test @MainActor func repeatedReleaseOrEnterCommitsOnlyOnce() {
        var state = OrbitDismissalState()
        state.begin()

        let firstCommit = state.beginCommit()

        #expect(firstCommit != nil)
        #expect(state.beginCommit() == nil)
        #expect(state.acceptsCompletion(for: firstCommit!))
    }

    @Test @MainActor func cancelDuringClipboardCopyInvalidatesThePendingPaste() {
        var state = OrbitDismissalState()
        state.begin()
        let pendingCopy = state.beginCommit()!

        let cancellationAnimation = state.beginDismissal()!

        #expect(!state.acceptsCompletion(for: pendingCopy))
        #expect(state.acceptsCompletion(for: cancellationAnimation))
        #expect(state.beginCommit() == nil)
    }

    @Test @MainActor func escapeDuringCollapseCanCloseImmediately() {
        var state = OrbitDismissalState()
        state.begin()
        let pendingAnimation = state.beginDismissal()!

        state.close()

        #expect(!state.isShowing)
        #expect(!state.acceptsCompletion(for: pendingAnimation))
        #expect(state.beginCommit() == nil)
    }

    @Test @MainActor func oldAnimationCannotCloseANewPresentation() {
        var state = OrbitDismissalState()
        state.begin()
        let oldAnimation = state.beginDismissal()!
        state.close()
        state.begin()

        #expect(!state.acceptsCompletion(for: oldAnimation))
        #expect(state.isShowing)
        #expect(state.beginCommit() != nil)
    }

    @Test @MainActor func cancelThenReleaseNeverStartsACommit() {
        var state = OrbitDismissalState()
        state.begin()
        state.close()

        #expect(state.beginCommit() == nil)
        #expect(state.beginDismissal() == nil)
    }

    @Test @MainActor func aCompletedCommitCanAnimateBeforeClosing() {
        var state = OrbitDismissalState()
        state.begin()
        let copy = state.beginCommit()!
        #expect(state.acceptsCompletion(for: copy))

        let closeAnimation = state.beginDismissal()!
        #expect(!state.acceptsCompletion(for: copy))
        #expect(state.acceptsCompletion(for: closeAnimation))

        state.close()
        #expect(!state.acceptsCompletion(for: closeAnimation))
    }
}
