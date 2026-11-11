//
//  LodgingBarTests.swift
//  outboundTests
//

import Foundation
import SwiftUI
import Testing
@testable import outbound

/// How the lodging bar is laid out on a day, and how it gets from one day to the next.
struct LodgingBarTests {
    private typealias Segment = LodgingBarSegment

    private func stay(_ id: String, _ phase: LodgingPhase) -> LodgingStay {
        let date = Date(timeIntervalSince1970: 0)
        let item = TripItem(
            id: id, tripId: "trip", kind: .lodging, title: id, displayTitle: id, notes: nil, tags: [],
            startsAtLocal: date, startsAtUtc: nil, startTimezone: nil,
            endsAtLocal: nil, endsAtUtc: nil, endTimezone: nil, imageUrl: nil,
            createdAt: date, updatedAt: date
        )
        return LodgingStay(item: item, phase: phase)
    }

    /// A segment as "name fraction", floor as "-": enough to read a layout at a glance.
    private func describe(_ segments: [Segment]) -> [String] {
        segments.map { segment in
            let name = switch segment.key {
            case .stay(let id): id
            case .gap: "-"
            }
            return "\(name) \(segment.fraction.formatted())"
        }
    }

    /// Moves a bar at rest on `from` to `to`.
    private func move(from: [LodgingStay], to: [LodgingStay], forward: Bool = true) -> LodgingBarTransition {
        Segment.transition(from: Segment.resting(for: from), to: to, forward: forward)
    }

    // MARK: - At rest

    @Test func aDayWithNoLodgingIsAllFloorInvitingAStay() {
        let segments = Segment.resting(for: [])

        #expect(describe(segments) == ["- 1"])
        #expect(segments[0].invitesAdd)
        #expect(!segments[0].leadingRule && !segments[0].trailingRule)
    }

    @Test func aLoneCheckInSitsAfterAQuarterOfFloor() {
        let segments = Segment.resting(for: [stay("A", .checkIn)])

        #expect(describe(segments) == ["- 0.25", "A 0.75"])
        #expect(segments[0].trailingRule)
        #expect(!segments[0].invitesAdd)
    }

    @Test func aLoneCheckOutSitsBeforeAQuarterOfFloor() {
        let segments = Segment.resting(for: [stay("A", .checkOut)])

        #expect(describe(segments) == ["A 0.75", "- 0.25"])
        #expect(segments[1].leadingRule)
    }

    @Test func aChangeoverPutsTheCheckOutFirstWithADividerBetween() {
        let segments = Segment.resting(for: [stay("B", .checkIn), stay("A", .checkOut)])

        #expect(describe(segments) == ["A 0.5", "B 0.5"])
        #expect(!segments[0].leadingRule)
        #expect(segments[1].leadingRule)
    }

    @Test func aNightMidStayFillsTheBar() {
        #expect(describe(Segment.resting(for: [stay("A", .staying)])) == ["A 1"])
    }

    // MARK: - Changing day

    @Test func checkInToStayingClosesTheFloorAndWidensTheStay() {
        let transition = move(from: [stay("A", .checkIn)], to: [stay("A", .staying)])

        #expect(describe(transition.staged) == ["- 0.25", "A 0.75"])
        #expect(describe(transition.settled) == ["- 0", "A 1"])
        #expect(transition.settled[0].isLeaving)
        // The stay is the same segment throughout, so it resizes rather than swaps.
        #expect(transition.settled[1].id == transition.staged[1].id)
        #expect(transition.settled[1].content == .stay(stay("A", .staying)))
    }

    @Test func stayingToCheckOutBringsFloorInFromTheTrailingEdge() {
        let transition = move(from: [stay("A", .staying)], to: [stay("A", .checkOut)])

        #expect(describe(transition.staged) == ["A 1", "- 0"])
        #expect(describe(transition.settled) == ["A 0.75", "- 0.25"])
    }

    @Test func aOneNightStaySlidesAcrossBetweenTwoStretchesOfFloor() {
        let transition = move(from: [stay("A", .checkIn)], to: [stay("A", .checkOut)])

        // The floor before the stay goes and different floor comes in after it; the
        // stay keeps its width and shifts over.
        #expect(describe(transition.staged) == ["- 0.25", "A 0.75", "- 0"])
        #expect(describe(transition.settled) == ["- 0", "A 0.75", "- 0.25"])
        #expect(transition.settled[0].isLeaving)
        #expect(transition.settled[0].id != transition.settled[2].id)
        #expect(transition.settled[1].id == transition.staged[1].id)
    }

    @Test func aOneNightStaySlidesBackTheOtherWay() {
        let transition = move(from: [stay("A", .checkOut)], to: [stay("A", .checkIn)], forward: false)

        #expect(describe(transition.staged) == ["- 0", "A 0.75", "- 0.25"])
        #expect(describe(transition.settled) == ["- 0.25", "A 0.75", "- 0"])
    }

    @Test func stayingToChangeoverBringsTheNextStayInFromTheTrailingEdge() {
        let transition = move(from: [stay("A", .staying)], to: [stay("A", .checkOut), stay("B", .checkIn)])

        #expect(describe(transition.staged) == ["A 1", "B 0"])
        #expect(describe(transition.settled) == ["A 0.5", "B 0.5"])
        // The arriving stay is laid out at its final width from the start, held to the
        // edge that slides.
        #expect(transition.staged[1].contentFraction == 0.5)
        #expect(transition.staged[1].pin == .leading)
    }

    @Test func changeoverToStayingSlidesTheOldStayOffTheLeadingEdge() {
        let transition = move(from: [stay("A", .checkOut), stay("B", .checkIn)], to: [stay("B", .staying)])

        #expect(describe(transition.settled) == ["A 0", "B 1"])
        #expect(transition.settled[0].isLeaving)
        #expect(transition.settled[0].contentFraction == 0.5)
        #expect(transition.settled[0].pin == .trailing)
        // Its divider goes with the stay it divided from.
        #expect(!transition.settled[1].leadingRule)
    }

    @Test func checkOutToNoLodgingWidensTheFloorOverTheStay() {
        let transition = move(from: [stay("A", .checkOut)], to: [])

        #expect(describe(transition.settled) == ["A 0", "- 1"])
        #expect(transition.settled[1].invitesAdd)
        #expect(!transition.settled[1].leadingRule)
        #expect(transition.settled[1].id == transition.staged[1].id)
    }

    @Test func noLodgingToCheckInBringsTheStayInOverTheFloor() {
        let transition = move(from: [], to: [stay("A", .checkIn)])

        #expect(describe(transition.staged) == ["- 1", "A 0"])
        #expect(transition.staged[0].invitesAdd)
        #expect(describe(transition.settled) == ["- 0.25", "A 0.75"])
        #expect(!transition.settled[0].invitesAdd)
    }

    @Test func goingBackFromNoLodgingBringsTheStayInFromTheLeadingEdge() {
        let transition = move(from: [], to: [stay("A", .checkOut)], forward: false)

        #expect(describe(transition.staged) == ["A 0", "- 1"])
        #expect(describe(transition.settled) == ["A 0.75", "- 0.25"])
        #expect(transition.staged[0].pin == .trailing)
    }

    @Test func checkOutThenCheckInElsewhereSlidesTheFloorAcross() {
        let transition = move(from: [stay("A", .checkOut)], to: [stay("B", .checkIn)])

        #expect(describe(transition.staged) == ["A 0.75", "- 0.25", "B 0"])
        #expect(describe(transition.settled) == ["A 0", "- 0.25", "B 0.75"])
    }

    @Test func jumpingBetweenUnrelatedStaysPushesInTheDirectionOfTravel() {
        let later = move(from: [stay("A", .staying)], to: [stay("C", .staying)], forward: true)
        #expect(describe(later.staged) == ["A 1", "C 0"])
        #expect(describe(later.settled) == ["A 0", "C 1"])
        #expect(later.settled[0].pin == .trailing)
        #expect(later.settled[1].pin == .leading)

        let earlier = move(from: [stay("C", .staying)], to: [stay("A", .staying)], forward: false)
        #expect(describe(earlier.staged) == ["A 0", "C 1"])
        #expect(describe(earlier.settled) == ["A 1", "C 0"])
        #expect(earlier.settled[0].pin == .trailing)
        #expect(earlier.settled[1].pin == .leading)
    }

    @Test func theSameArrangementNeedsNoStaging() {
        let current = Segment.resting(for: [stay("A", .staying)])
        let transition = Segment.transition(from: current, to: [stay("A", .staying)], forward: true)

        #expect(transition.staged == current)
        #expect(transition.settled == current)
    }

    @Test func aStayStillSlidingOffComesBackWhenTheDayIsReturnedTo() {
        // Changeover → staying at B, then back before A has finished sliding off.
        let first = move(from: [stay("A", .checkOut), stay("B", .checkIn)], to: [stay("B", .staying)])
        let back = Segment.transition(from: first.settled, to: [stay("A", .checkOut), stay("B", .checkIn)], forward: false)

        #expect(back.staged == first.settled)
        #expect(describe(back.settled) == ["A 0.5", "B 0.5"])
        #expect(back.settled.allSatisfy { !$0.isLeaving })
        #expect(back.settled.map(\.id) == first.settled.map(\.id))
    }

    @Test func segmentsStillSlidingOffKeepGoingThroughAnotherChange() {
        // Check-in → staying leaves floor sliding off; moving on to check-out before
        // it's gone brings new floor in on the other side.
        let first = move(from: [stay("A", .checkIn)], to: [stay("A", .staying)])
        let second = Segment.transition(from: first.settled, to: [stay("A", .checkOut)], forward: true)

        #expect(describe(second.settled) == ["- 0", "A 0.75", "- 0.25"])
        #expect(second.settled[0].isLeaving)
        #expect(!second.settled[2].isLeaving)
    }

    // MARK: - Without sliding

    @Test func swappingKeepsIdentityOnlyForTheSameArrangement() {
        let current = Segment.resting(for: [stay("A", .staying)])

        let same = Segment.resting(for: [stay("A", .staying)], keepingIdentityOf: current)
        #expect(same.map(\.id) == current.map(\.id))

        let resized = Segment.resting(for: [stay("A", .checkOut)], keepingIdentityOf: current)
        #expect(resized.allSatisfy { $0.id != current[0].id })
    }
}
