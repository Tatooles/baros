import Foundation
import SwiftData

enum ModelContainerFactory {
    static func makeModelContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema(BarosSchema.models)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isStoredInMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func resetPersistentStoreFiles() throws {
        let fileManager = FileManager.default
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeFilenames = ["default.store", "default.store-shm", "default.store-wal"]

        for filename in storeFilenames {
            let fileURL = applicationSupportURL.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }
}
