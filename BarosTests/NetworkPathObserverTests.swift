import XCTest
@testable import Baros

@MainActor
final class NetworkPathObserverTests: XCTestCase {
    func testPathUpdatesPublishCoarseAvailabilityChanges() {
        let monitor = TestNetworkPathMonitor()
        let observer = NetworkPathObserver(
            monitor: monitor,
            makeRecoveryCandidate: { true }
        )
        var receivedAvailability: [NetworkAvailability] = []

        observer.start(
            onAvailabilityChange: { availability in
                receivedAvailability.append(availability)
            },
            onNetworkRecovery: { _ in }
        )
        monitor.send(.unsatisfied)
        monitor.send(.requiresConnection)
        monitor.send(.satisfied)

        XCTAssertEqual(receivedAvailability, [.unavailable, .available])
    }

    func testInitialSatisfiedPathEstablishesBaselineWithoutRecovery() async throws {
        let monitor = TestNetworkPathMonitor()
        let observer = NetworkPathObserver(
            monitor: monitor,
            settlingDelay: .milliseconds(10),
            makeRecoveryCandidate: { true }
        )
        var recoveryCount = 0

        observer.start { _ in
            recoveryCount += 1
        }
        monitor.send(.satisfied)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(recoveryCount, 0)
    }

    func testUnsatisfiedToSatisfiedPathEmitsRecoveryAfterSettling() async throws {
        let monitor = TestNetworkPathMonitor()
        let observer = NetworkPathObserver(
            monitor: monitor,
            settlingDelay: .milliseconds(10),
            makeRecoveryCandidate: { true }
        )
        var recoveryCount = 0

        observer.start { _ in
            recoveryCount += 1
        }
        monitor.send(.unsatisfied)
        monitor.send(.satisfied)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(recoveryCount, 1)
    }

    func testRequiresConnectionToSatisfiedAlsoEmitsRecovery() async throws {
        let monitor = TestNetworkPathMonitor()
        let observer = NetworkPathObserver(
            monitor: monitor,
            settlingDelay: .milliseconds(10),
            makeRecoveryCandidate: { true }
        )
        var recoveryCount = 0

        observer.start { _ in
            recoveryCount += 1
        }
        monitor.send(.requiresConnection)
        monitor.send(.satisfied)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(recoveryCount, 1)
    }

    func testFlappingPathCoalescesToOneSettledRecovery() async throws {
        let monitor = TestNetworkPathMonitor()
        let observer = NetworkPathObserver(
            monitor: monitor,
            settlingDelay: .milliseconds(20),
            makeRecoveryCandidate: { true }
        )
        var recoveryCount = 0

        observer.start { _ in
            recoveryCount += 1
        }
        monitor.send(.unsatisfied)
        monitor.send(.satisfied)
        try await Task.sleep(for: .milliseconds(5))
        monitor.send(.unsatisfied)
        monitor.send(.satisfied)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(recoveryCount, 1)
    }

    func testPathDropDuringSettlingCancelsRecovery() async throws {
        let monitor = TestNetworkPathMonitor()
        let observer = NetworkPathObserver(
            monitor: monitor,
            settlingDelay: .milliseconds(20),
            makeRecoveryCandidate: { true }
        )
        var recoveryCount = 0

        observer.start { _ in
            recoveryCount += 1
        }
        monitor.send(.unsatisfied)
        monitor.send(.satisfied)
        try await Task.sleep(for: .milliseconds(5))
        monitor.send(.unsatisfied)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(recoveryCount, 0)
    }

    func testRepeatedIdenticalStatusesDoNotDuplicateRecovery() async throws {
        let monitor = TestNetworkPathMonitor()
        let observer = NetworkPathObserver(
            monitor: monitor,
            settlingDelay: .milliseconds(10),
            makeRecoveryCandidate: { true }
        )
        var recoveryCount = 0

        observer.start { _ in
            recoveryCount += 1
        }
        monitor.send(.unsatisfied)
        monitor.send(.unsatisfied)
        monitor.send(.satisfied)
        monitor.send(.satisfied)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(recoveryCount, 1)
    }

    func testCancellationDuringSettlingPreventsRecovery() async throws {
        let monitor = TestNetworkPathMonitor()
        let observer = NetworkPathObserver(
            monitor: monitor,
            settlingDelay: .milliseconds(20),
            makeRecoveryCandidate: { true }
        )
        var recoveryCount = 0

        observer.start { _ in
            recoveryCount += 1
        }
        monitor.send(.unsatisfied)
        monitor.send(.satisfied)
        observer.cancel()
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(recoveryCount, 0)
    }

    func testStartingTwiceDoesNotStartTwoMonitors() {
        let monitor = TestNetworkPathMonitor()
        let observer = NetworkPathObserver(
            monitor: monitor,
            makeRecoveryCandidate: { true }
        )

        observer.start { _ in }
        observer.start { _ in }

        XCTAssertEqual(monitor.startCount, 1)
    }

    func testRecoveryCarriesCandidateCapturedBeforeSettling() async throws {
        let monitor = TestNetworkPathMonitor()
        let candidateSource = TestRecoveryCandidateSource("owner-a|session-a")
        let observer = NetworkPathObserver(
            monitor: monitor,
            settlingDelay: .milliseconds(20),
            makeRecoveryCandidate: { candidateSource.value }
        )
        var recoveredCandidate: String?

        observer.start { candidate in
            recoveredCandidate = candidate
        }
        monitor.send(.unsatisfied)
        monitor.send(.satisfied)
        candidateSource.value = "owner-b|session-b"
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(recoveredCandidate, "owner-a|session-a")
    }

    func testInactiveSceneCannotCreateRecoveryCandidate() {
        let activity = NetworkRecoveryActivity()

        let candidate = activity.makeCandidate { true }

        XCTAssertNil(candidate)
    }

    func testSceneDeactivationInvalidatesCandidateAfterReactivation() {
        let activity = NetworkRecoveryActivity()
        activity.setActive(true)
        let candidate = activity.makeCandidate { true }
        var recoveryCount = 0

        activity.setActive(false)
        activity.setActive(true)
        if let candidate {
            activity.performIfCurrent(candidate) { _ in
                recoveryCount += 1
            }
        }

        XCTAssertEqual(recoveryCount, 0)
    }

    func testRecoveryTransitionObservedWhileInactiveStaysCancelledAfterActivation() async throws {
        let monitor = TestNetworkPathMonitor()
        let activity = NetworkRecoveryActivity()
        let observer = NetworkPathObserver(
            monitor: monitor,
            settlingDelay: .milliseconds(20),
            makeRecoveryCandidate: { activity.makeCandidate { true } }
        )
        var recoveryCount = 0

        observer.start { candidate in
            activity.performIfCurrent(candidate) { _ in
                recoveryCount += 1
            }
        }
        monitor.send(.unsatisfied)
        monitor.send(.satisfied)
        activity.setActive(true)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(recoveryCount, 0)
    }

    func testDeactivationDuringSettlingCancelsRecoveryAfterReactivation() async throws {
        let monitor = TestNetworkPathMonitor()
        let activity = NetworkRecoveryActivity()
        activity.setActive(true)
        let observer = NetworkPathObserver(
            monitor: monitor,
            settlingDelay: .milliseconds(20),
            makeRecoveryCandidate: { activity.makeCandidate { true } }
        )
        var recoveryCount = 0

        observer.start { candidate in
            activity.performIfCurrent(candidate) { _ in
                recoveryCount += 1
            }
        }
        monitor.send(.unsatisfied)
        monitor.send(.satisfied)
        activity.setActive(false)
        activity.setActive(true)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(recoveryCount, 0)
    }
}

@MainActor
private final class TestRecoveryCandidateSource {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

@MainActor
private final class TestNetworkPathMonitor: NetworkPathMonitoring {
    private var receiveStatus: (@MainActor @Sendable (NetworkPathStatus) -> Void)?
    private(set) var startCount = 0

    func start(
        receiveStatus: @escaping @MainActor @Sendable (NetworkPathStatus) -> Void
    ) {
        startCount += 1
        self.receiveStatus = receiveStatus
    }

    func cancel() {
        receiveStatus = nil
    }

    func send(_ status: NetworkPathStatus) {
        receiveStatus?(status)
    }
}
