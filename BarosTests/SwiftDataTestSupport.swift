import Foundation
import SwiftData
@testable import Baros

@MainActor
enum SwiftDataTestSupport {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(BarosSchema.models)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeDiskBackedContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema(BarosSchema.models)
        let configuration = ModelConfiguration(url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
