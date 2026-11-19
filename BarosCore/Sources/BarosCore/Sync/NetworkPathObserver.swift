import Foundation
import Network

public enum NetworkAvailability: Equatable {
    case unknown
    case available
    case requiresConnection
    case unavailable
}

public enum NetworkPathStatus: Equatable, Sendable {
    case satisfied
    case unsatisfied
    case requiresConnection
}

private extension NetworkAvailability {
    init(pathStatus: NetworkPathStatus) {
        self = switch pathStatus {
        case .satisfied:
            .available
        case .requiresConnection:
            .requiresConnection
        case .unsatisfied:
            .unavailable
        }
    }
}

@MainActor
public final class NetworkRecoveryActivity {
    public init() {}

    public struct Candidate<Value> {
        fileprivate let generation: UInt
        let value: Value
    }

    private(set) var isActive = false
    private var generation: UInt = 0

    public func setActive(_ isActive: Bool) {
        if self.isActive, !isActive {
            generation &+= 1
        }
        self.isActive = isActive
    }

    public func makeCandidate<Value>(
        _ makeValue: () -> Value?
    ) -> Candidate<Value>? {
        guard isActive, let value = makeValue() else { return nil }
        return Candidate(generation: generation, value: value)
    }

    public func performIfCurrent<Value>(
        _ candidate: Candidate<Value>,
        _ action: (Value) -> Void
    ) {
        guard isActive, candidate.generation == generation else { return }
        action(candidate.value)
    }
}

@MainActor
public protocol NetworkPathMonitoring: AnyObject {
    func start(
        receiveStatus: @escaping @MainActor @Sendable (NetworkPathStatus) -> Void
    )
    func cancel()
}

@MainActor
public final class SystemNetworkPathMonitor: NetworkPathMonitoring {
    public init() {}

    private let queue = DispatchQueue(label: "com.tatooles.baros.network-path")
    private var monitor: NWPathMonitor?
    private var statusContinuation: AsyncStream<NetworkPathStatus>.Continuation?
    private var deliveryTask: Task<Void, Never>?

    public func start(
        receiveStatus: @escaping @MainActor @Sendable (NetworkPathStatus) -> Void
    ) {
        cancel()

        let statuses = AsyncStream<NetworkPathStatus>.makeStream()
        statusContinuation = statuses.continuation
        deliveryTask = Task { @MainActor in
            for await status in statuses.stream {
                guard !Task.isCancelled else { break }
                receiveStatus(status)
            }
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let status: NetworkPathStatus = switch path.status {
            case .satisfied:
                .satisfied
            case .unsatisfied:
                .unsatisfied
            case .requiresConnection:
                .requiresConnection
            @unknown default:
                .unsatisfied
            }
            statuses.continuation.yield(status)
        }
        self.monitor = monitor
        monitor.start(queue: queue)
    }

    public func cancel() {
        monitor?.cancel()
        monitor = nil
        statusContinuation?.finish()
        statusContinuation = nil
        deliveryTask?.cancel()
        deliveryTask = nil
    }

    deinit {
        monitor?.cancel()
        statusContinuation?.finish()
        deliveryTask?.cancel()
    }
}

@MainActor
public final class NetworkPathObserver<RecoveryCandidate> {
    private let monitor: any NetworkPathMonitoring
    private let settlingDelay: Duration
    private let makeRecoveryCandidate: @MainActor () -> RecoveryCandidate?
    private var latestStatus: NetworkPathStatus?
    private var settlingTask: Task<Void, Never>?
    private var isStarted = false

    public init(
        monitor: any NetworkPathMonitoring = SystemNetworkPathMonitor(),
        settlingDelay: Duration = .milliseconds(500),
        makeRecoveryCandidate: @MainActor @escaping () -> RecoveryCandidate?
    ) {
        self.monitor = monitor
        self.settlingDelay = settlingDelay
        self.makeRecoveryCandidate = makeRecoveryCandidate
    }

    public func start(
        onAvailabilityChange: @escaping @MainActor (NetworkAvailability) -> Void = { _ in },
        onNetworkRecovery: @escaping @MainActor (RecoveryCandidate) -> Void
    ) {
        guard !isStarted else { return }
        isStarted = true

        monitor.start { [weak self] status in
            guard let self else { return }
            handle(
                status,
                onAvailabilityChange: onAvailabilityChange,
                onNetworkRecovery: onNetworkRecovery
            )
        }
    }

    func cancel() {
        isStarted = false
        latestStatus = nil
        settlingTask?.cancel()
        settlingTask = nil
        monitor.cancel()
    }

    private func handle(
        _ status: NetworkPathStatus,
        onAvailabilityChange: @escaping @MainActor (NetworkAvailability) -> Void,
        onNetworkRecovery: @escaping @MainActor (RecoveryCandidate) -> Void
    ) {
        guard status != latestStatus else { return }

        let previousStatus = latestStatus
        latestStatus = status
        let availability = NetworkAvailability(pathStatus: status)
        if previousStatus.map(NetworkAvailability.init(pathStatus:)) != availability {
            onAvailabilityChange(availability)
        }
        settlingTask?.cancel()
        settlingTask = nil

        guard status == .satisfied,
              previousStatus == .unsatisfied || previousStatus == .requiresConnection,
              let recoveryCandidate = makeRecoveryCandidate() else {
            return
        }

        settlingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: settlingDelay)
            guard !Task.isCancelled, latestStatus == .satisfied else { return }
            settlingTask = nil
            onNetworkRecovery(recoveryCandidate)
        }
    }
}
