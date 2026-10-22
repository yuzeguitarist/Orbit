//
//  OrbitTests.swift
//  OrbitTests
//
//  Created by Yuze Pan on 1/7/26.
//

import Testing
import CoreGraphics
@testable import Orbit

struct OrbitTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test @MainActor func cardDragStateRenderingEquivalenceOnlyCoalescesSubpixelDrag() async throws {
        let current = CardDragState.dragging(offset: CGSize(width: 10, height: 20))

        #expect(current.isEquivalentForRendering(to: .dragging(offset: CGSize(width: 10.25, height: 20.25))))
        #expect(!current.isEquivalentForRendering(to: .dragging(offset: CGSize(width: 11, height: 20))))
        #expect(!current.isEquivalentForRendering(to: .nearBlackHole(offset: CGSize(width: 10.25, height: 20.25))))
        #expect(!CardDragState.releasedInBlackHole(offset: .zero).isEquivalentForRendering(to: .releasedInBlackHole(offset: CGSize(width: 0.25, height: 0.25))))
    }

    @Test @MainActor func arcLayoutPrecomputedValuesMatchExistingGeometryFormula() async throws {
        let layout = ArcLayout(index: 2, totalCount: 9, selectedIndex: 1, animationProgress: 1)
        let expectedOrbitAngle = 52.0 // 9 cards use 26 degrees per step.

        #expect(abs(layout.orbitAngle - expectedOrbitAngle) < 0.0001)
        #expect(abs(layout.cardRotation - (-expectedOrbitAngle * 0.04)) < 0.0001)
        #expect(layout.zIndex == 7)
    }

}
