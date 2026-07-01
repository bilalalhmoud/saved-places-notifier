import XCTest
@testable import SavedPlacesCore

final class ProximityEngineTests: XCTestCase {
    private let engine = ProximityEngine()
    private let center = Coordinate(latitude: 51.5000, longitude: -0.1200)
    private let far = Coordinate(latitude: 51.7000, longitude: -0.1200) // ~22 km away

    private func makeIndex(_ places: [PlaceRecord]) -> SpatialIndex {
        let index = SpatialIndex()
        index.build(from: places.map { $0.indexed })
        return index
    }

    private func nearbyPlace(category: String = "Restaurants") -> PlaceRecord {
        PlaceRecord(
            title: "Dishoom",
            coordinate: Coordinate(latitude: 51.5008, longitude: -0.1200), // ~89 m
            category: category
        )
    }

    func testEntryEmitsEvent() {
        let place = nearbyPlace()
        let index = makeIndex([place])
        let config = ProximityConfig(baseRadiusMeters: 500, cooldown: .untilLeave)

        let outcome = engine.evaluate(
            current: center, mode: .any, index: index,
            categoryProvider: { _ in place.category },
            config: config, state: ProximityState(), now: Date()
        )

        XCTAssertEqual(outcome.events.count, 1)
        XCTAssertEqual(outcome.events.first?.id, place.id)
        XCTAssertEqual(outcome.state.places[place.id]?.wasInside, true)
    }

    func testNoRepeatWhileContinuouslyInside() {
        let place = nearbyPlace()
        let index = makeIndex([place])
        let config = ProximityConfig(baseRadiusMeters: 500, cooldown: .untilLeave)
        let t0 = Date()

        let first = engine.evaluate(current: center, mode: .any, index: index,
                                    categoryProvider: { _ in place.category },
                                    config: config, state: ProximityState(), now: t0)
        let second = engine.evaluate(current: center, mode: .any, index: index,
                                     categoryProvider: { _ in place.category },
                                     config: config, state: first.state, now: t0.addingTimeInterval(60))

        XCTAssertEqual(first.events.count, 1)
        XCTAssertEqual(second.events.count, 0, "must not re-notify while still inside")
    }

    func testLeaveAndReturnReNotifies() {
        let place = nearbyPlace()
        let index = makeIndex([place])
        let config = ProximityConfig(baseRadiusMeters: 500, cooldown: .untilLeave)
        let t0 = Date()

        let enter = engine.evaluate(current: center, mode: .any, index: index,
                                    categoryProvider: { _ in place.category },
                                    config: config, state: ProximityState(), now: t0)
        let leave = engine.evaluate(current: far, mode: .any, index: index,
                                    categoryProvider: { _ in place.category },
                                    config: config, state: enter.state, now: t0.addingTimeInterval(120))
        let reenter = engine.evaluate(current: center, mode: .any, index: index,
                                      categoryProvider: { _ in place.category },
                                      config: config, state: leave.state, now: t0.addingTimeInterval(600))

        XCTAssertEqual(enter.events.count, 1)
        XCTAssertEqual(leave.events.count, 0)
        XCTAssertEqual(leave.state.places[place.id]?.wasInside, false)
        XCTAssertEqual(reenter.events.count, 1, "returning should notify again")
    }

    func testHourlyCooldownBlocksQuickReturn() {
        let place = nearbyPlace()
        let index = makeIndex([place])
        let config = ProximityConfig(baseRadiusMeters: 500, cooldown: .oneHour)
        let t0 = Date()

        let enter = engine.evaluate(current: center, mode: .any, index: index,
                                    categoryProvider: { _ in place.category },
                                    config: config, state: ProximityState(), now: t0)
        let leave = engine.evaluate(current: far, mode: .any, index: index,
                                    categoryProvider: { _ in place.category },
                                    config: config, state: enter.state, now: t0.addingTimeInterval(300))
        let quickReturn = engine.evaluate(current: center, mode: .any, index: index,
                                          categoryProvider: { _ in place.category },
                                          config: config, state: leave.state, now: t0.addingTimeInterval(1800))
        let laterReturn = engine.evaluate(current: center, mode: .any, index: index,
                                          categoryProvider: { _ in place.category },
                                          config: config, state: quickReturn.state, now: t0.addingTimeInterval(7200))

        XCTAssertEqual(enter.events.count, 1)
        XCTAssertEqual(quickReturn.events.count, 0, "within the hour cooldown must stay silent")
        XCTAssertEqual(laterReturn.events.count, 1, "after the cooldown it may notify again")
    }

    func testDisabledCategoryIsFiltered() {
        let place = nearbyPlace(category: "Museums")
        let index = makeIndex([place])
        let config = ProximityConfig(baseRadiusMeters: 500, cooldown: .untilLeave,
                                     enabledCategories: ["Restaurants", "Coffee"])

        let outcome = engine.evaluate(current: center, mode: .any, index: index,
                                      categoryProvider: { _ in place.category },
                                      config: config, state: ProximityState(), now: Date())
        XCTAssertEqual(outcome.events.count, 0, "disabled categories should never notify")
    }

    func testBatchCapLimitsEmittedEvents() {
        // Five nearby coffee shops, batch cap of 3.
        var places: [PlaceRecord] = []
        for i in 0..<5 {
            places.append(PlaceRecord(
                title: "Coffee \(i)",
                coordinate: Coordinate(latitude: 51.5001 + Double(i) * 0.0001, longitude: -0.1200),
                category: "Coffee"
            ))
        }
        let index = makeIndex(places)
        let categories = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0.category ?? "") })
        let config = ProximityConfig(baseRadiusMeters: 500, cooldown: .untilLeave, maxNotificationsPerBatch: 3)

        let outcome = engine.evaluate(current: center, mode: .any, index: index,
                                      categoryProvider: { categories[$0] },
                                      config: config, state: ProximityState(), now: Date())
        XCTAssertEqual(outcome.events.count, 3, "batch cap should limit emitted events")
    }

    func testGlobalRateLimitSuppressesButKeepsPending() {
        let place = nearbyPlace()
        let other = PlaceRecord(title: "Other", coordinate: Coordinate(latitude: 51.5009, longitude: -0.1201), category: "Restaurants")
        let index = makeIndex([place, other])
        let config = ProximityConfig(baseRadiusMeters: 500, cooldown: .untilLeave,
                                     minSecondsBetweenNotifications: 600)
        let t0 = Date()

        let first = engine.evaluate(current: center, mode: .any, index: makeIndex([place]),
                                    categoryProvider: { _ in "Restaurants" },
                                    config: config, state: ProximityState(), now: t0)
        // A brand-new place appears 60 s later — still within the global rate limit.
        let second = engine.evaluate(current: center, mode: .any, index: index,
                                     categoryProvider: { _ in "Restaurants" },
                                     config: config, state: first.state, now: t0.addingTimeInterval(60))

        XCTAssertEqual(first.events.count, 1)
        XCTAssertEqual(second.events.count, 0, "rate limit suppresses within the interval")
        XCTAssertNotEqual(second.state.places[other.id]?.wasInside, true,
                          "suppressed place stays pending, not marked as notified")
    }

    func testAdaptiveRadiusByMode() {
        // A place ~700 m away: outside walking radius but inside driving radius.
        let place = PlaceRecord(title: "Bakery",
                                coordinate: Coordinate(latitude: 51.5063, longitude: -0.1200), // ~700 m
                                category: "Food")
        let index = makeIndex([place])
        let config = ProximityConfig(baseRadiusMeters: 500, cooldown: .untilLeave)

        let walking = engine.evaluate(current: center, mode: .walking, index: index,
                                      categoryProvider: { _ in place.category },
                                      config: config, state: ProximityState(), now: Date())
        let driving = engine.evaluate(current: center, mode: .driving, index: index,
                                      categoryProvider: { _ in place.category },
                                      config: config, state: ProximityState(), now: Date())

        XCTAssertEqual(walking.events.count, 0, "700 m is beyond the walking radius")
        XCTAssertEqual(driving.events.count, 1, "700 m is within the driving radius")
    }
}
