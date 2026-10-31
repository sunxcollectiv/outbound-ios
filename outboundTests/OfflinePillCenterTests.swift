//
//  OfflinePillCenterTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// How the offline pill picks its spot and words from the screens on display: the
/// latest screen wins, popups only move it, and screens on their way out are skipped.
@MainActor
struct OfflinePillCenterTests {
    private func placement(
        _ bottomY: CGFloat, isForm: Bool = false, savedDate: Date? = nil, keepsScreenBelow: Bool = false
    ) -> OfflinePillCenter.Placement {
        .init(bottomY: bottomY, isForm: isForm, savedDate: savedDate, showsWhenOnline: false, isHidden: false, keepsScreenBelow: keepsScreenBelow)
    }

    @Test func nothingPlacedMeansNoPill() {
        #expect(OfflinePillCenter().current == nil)
    }

    @Test func theLatestScreenWins() {
        let center = OfflinePillCenter()
        center.set(placement(800), for: UUID())
        center.set(placement(700, isForm: true), for: UUID())

        #expect(center.current?.bottomY == 700)
        #expect(center.current?.isForm == true)
    }

    @Test func updatingAScreenKeepsItsPlaceInLine() {
        let center = OfflinePillCenter()
        let below = UUID()
        center.set(placement(800), for: below)
        center.set(placement(700), for: UUID())
        center.set(placement(780), for: below)

        #expect(center.current?.bottomY == 700)
    }

    @Test func removingTheTopScreenFallsBackToTheOneBelow() {
        let center = OfflinePillCenter()
        let top = UUID()
        center.set(placement(800), for: UUID())
        center.set(placement(700), for: top)
        center.remove(top)

        #expect(center.current?.bottomY == 800)
    }

    @Test func aPopupMovesThePillButKeepsTheWordsBelow() {
        let center = OfflinePillCenter()
        center.set(placement(700, isForm: true), for: UUID())
        center.set(placement(824, keepsScreenBelow: true), for: UUID())

        #expect(center.current?.bottomY == 824)
        #expect(center.current?.isForm == true)
    }

    @Test func aDetailSheetKeepsTheSavedDateBelow() {
        let saved = Date(timeIntervalSince1970: 1_000)
        let center = OfflinePillCenter()
        center.set(placement(780, savedDate: saved), for: UUID())
        center.set(placement(824, keepsScreenBelow: true), for: UUID())

        #expect(center.current?.savedDate == saved)
    }

    @Test func screensOnTheirWayOutAreSkipped() {
        let center = OfflinePillCenter()
        center.set(placement(780), for: UUID())
        // A sheet sliding off the bottom reports a spot below the screen.
        center.set(placement(950, isForm: true), for: UUID())

        let target = center.current { $0.bottomY > 874 }
        #expect(target?.bottomY == 780)
        #expect(target?.isForm == false)
    }
}
