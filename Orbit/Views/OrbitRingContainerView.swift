//
//  OrbitRingContainerView.swift
//  Orbit
//
//  Created by Yuze Pan on 1/10/26.
//

import SwiftUI

struct OrbitRingContainerView: View {
    @ObservedObject var coordinator: OrbitRingCoordinator
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            switch coordinator.mode {
            case .apps:
                OrbitRingView(viewModel: coordinator.appViewModel, onDismiss: onDismiss)
            case .clipboard:
                ClipboardRingView(viewModel: coordinator.clipboardViewModel)
            }
        }
    }
}
