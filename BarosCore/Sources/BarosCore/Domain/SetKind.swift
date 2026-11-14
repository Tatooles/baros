import Foundation

public enum SetKind: String, CaseIterable, Codable, Identifiable {
    case working
    case warmup
    case drop
    case failure

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .working:
            return "Working"
        case .warmup:
            return "Warmup"
        case .drop:
            return "Drop"
        case .failure:
            return "Failure"
        }
    }
}
