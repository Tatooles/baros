import SwiftData
@testable import Baros

@MainActor
enum SwiftDataTestSupport {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(BarosSchema.models)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
