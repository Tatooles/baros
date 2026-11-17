import Foundation

public struct ActiveWorkoutSetSaveFailure {
    public enum Operation: String {
        case fieldEdit = "field_edit"
        case completion
        case rpe
    }

    public static let knownDomains: Set<String> = [NSCocoaErrorDomain, NSPOSIXErrorDomain, "NSSQLiteErrorDomain"]
    public let operation: Operation
    public let domain: String
    public let code: String

    init(operation: Operation, error: Error) {
        let error = error as NSError
        self.operation = operation
        let known = Self.knownDomains.contains(error.domain)
        domain = known ? error.domain : "other"
        code = known ? String(error.code) : "unknown"
    }
}
