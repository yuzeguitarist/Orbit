import Testing
@testable import Orbit

struct OrbitDismissalTests {
    @Test @MainActor func repeatedReleaseOrEnterCommitsOnlyOnce() throws {
        var state = OrbitDismissalState()
        state.begin()

        let firstCommit = try #require(state.beginCommit())

        #expect(state.beginCommit() == nil)
        #expect(state.acceptsCompletion(for: firstCommit))
    }

    @Test @MainActor func cancelDuringClipboardCopyInvalidatesThePendingPaste() throws {
        var state = OrbitDismissalState()
        state.begin()
        let pendingCopy = try #require(state.beginCommit())

        let cancellationAnimation = try #require(state.beginDismissal())

        #expect(!state.acceptsCompletion(for: pendingCopy))
        #expect(state.acceptsCompletion(for: cancellationAnimation))
        #expect(state.beginCommit() == nil)
    }

    @Test @MainActor func escapeDuringCollapseCanCloseImmediately() throws {
        var state = OrbitDismissalState()
        state.begin()
        let pendingAnimation = try #require(state.beginDismissal())

        state.close()

        #expect(!state.isShowing)
        #expect(!state.acceptsCompletion(for: pendingAnimation))
        #expect(state.beginCommit() == nil)
    }

    @Test @MainActor func oldAnimationCannotCloseANewPresentation() throws {
        var state = OrbitDismissalState()
        state.begin()
        let oldAnimation = try #require(state.beginDismissal())
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

    @Test @MainActor func aCompletedCommitCanAnimateBeforeClosing() throws {
        var state = OrbitDismissalState()
        state.begin()
        let copy = try #require(state.beginCommit())
        #expect(state.acceptsCompletion(for: copy))

        let closeAnimation = try #require(state.beginDismissal())
        #expect(!state.acceptsCompletion(for: copy))
        #expect(state.acceptsCompletion(for: closeAnimation))

        state.close()
        #expect(!state.acceptsCompletion(for: closeAnimation))
    }
}
