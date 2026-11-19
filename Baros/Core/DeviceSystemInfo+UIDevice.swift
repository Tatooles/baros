import BarosCore
import UIKit

extension DeviceSystemInfo {
    @MainActor
    static var current: DeviceSystemInfo {
        let device = UIDevice.current
        return DeviceSystemInfo(
            model: device.model,
            systemName: device.systemName,
            systemVersion: device.systemVersion
        )
    }
}
