//
//  OrbitRingContainerView.swift
//  Orbit
//
//  Created by Yuze Pan on 1/10/26.
//

import SwiftUI

struct OrbitRingContainerView: View {
    @ObservedObject var coordinator: OrbitRingCoordinator
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
            switch coordinator.mode {
            case .apps:
                OrbitRingView(viewModel: coordinator.appViewModel, onCommit: onCommit)
            case .clipboard:
                ClipboardRingView(viewModel: coordinator.clipboardViewModel)
            }
        }
    }
}
