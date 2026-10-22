//
//  OrbitRingCoordinator.swift
//  Orbit
//
//  Created by Yuze Pan on 1/10/26.
//

import Combine
import CoreGraphics
import Foundation

@MainActor
final class OrbitRingCoordinator: ObservableObject {
    enum Mode {
        case apps
        case clipboard
    }

    @Published var mode: Mode = .apps

    let appViewModel = OrbitViewModel()
    let clipboardViewModel = ClipboardRingViewModel()

    private(set) var isTransitioning = false
    private var pendingMode: Mode?
    private var presentationID = UUID()
    private var transitionID = UUID()

    var currentPresentationID: UUID {
        presentationID
    }

    func prepareForShow(
        at location: CGPoint,
        contextAppId: String?,
        excludingProcessIdentifier: pid_t? = nil,
        autoSelectFirstApp: Bool = false
    ) {
        presentationID = UUID()
        transitionID = UUID()
        isTransitioning = false
        pendingMode = nil
        mode = .apps
        appViewModel.resetPresentationState()
        appViewModel.setContextAppId(contextAppId)
        appViewModel.refreshApps(excludingProcessIdentifier: excludingProcessIdentifier)
        if autoSelectFirstApp, appViewModel.appCount > 0 {
            appViewModel.selectByIndex(0)
        }
        appViewModel.setAnchorPosition(location)
        clipboardViewModel.resetState()
    }

    func resetAfterDismiss() {
        presentationID = UUID()
        transitionID = UUID()
        isTransitioning = false
        pendingMode = nil
        mode = .apps
        appViewModel.resetPresentationState()
        clipboardViewModel.resetState()
    }

    func toggleMode() {
        if isTransitioning {
            pendingMode = mode == .apps ? .clipboard : .apps
            return
        }

        switch mode {
        case .apps:
            switchToClipboard()
        case .clipboard:
            switchToApps()
        }
    }

    func switchToClipboard() {
        guard mode == .apps, !isTransitioning else { return }
        let currentPresentationID = presentationID
        let currentTransitionID = UUID()
        transitionID = currentTransitionID
        isTransitioning = true

        clipboardViewModel.deactivatePresentation()
        clipboardViewModel.loadItemsForRing()

        appViewModel.startCollapseAnimation { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.presentationID == currentPresentationID else { return }
                guard self.transitionID == currentTransitionID else { return }
                self.mode = .clipboard
                self.clipboardViewModel.activatePresentation()
                self.finishTransition()
            }
        }
    }

    func switchToApps() {
        guard mode == .clipboard, !isTransitioning else { return }
        let currentPresentationID = presentationID
        let currentTransitionID = UUID()
        transitionID = currentTransitionID
        isTransitioning = true

        clipboardViewModel.deactivatePresentation()

        clipboardViewModel.startCollapseAnimation { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.presentationID == currentPresentationID else { return }
                guard self.transitionID == currentTransitionID else { return }
                self.mode = .apps
                self.finishTransition()
            }
        }
    }

    private func finishTransition() {
        isTransitioning = false
        guard let pending = pendingMode, pending != mode else {
            pendingMode = nil
            return
        }
        pendingMode = nil
        switch pending {
        case .apps:
            switchToApps()
        case .clipboard:
            switchToClipboard()
        }
    }
}
