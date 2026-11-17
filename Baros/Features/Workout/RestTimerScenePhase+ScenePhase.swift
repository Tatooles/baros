import BarosCore
import SwiftUI

extension RestTimerScenePhase {
    init(_ phase: ScenePhase) {
        self = phase == .background ? .background : .foreground
    }
}
