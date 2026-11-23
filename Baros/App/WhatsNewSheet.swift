import BarosCore
import SwiftUI

struct WhatsNewSheet: View {
    let sheetID: WhatsNewSheetID
    let onDismiss: () -> Void

    @ViewBuilder
    var body: some View {
        switch sheetID {
        case .version1_0:
            WhatsNewVersion1_0View(onDismiss: onDismiss)
        case .version1_2:
            WhatsNewVersion1_2View(onDismiss: onDismiss)
        case .version1_3:
            WhatsNewVersion1_3View(onDismiss: onDismiss)
        case .version1_4:
            WhatsNewVersion1_4View(onDismiss: onDismiss)
        case .version1_5:
            WhatsNewVersion1_5View(onDismiss: onDismiss)
        case .version1_6:
            WhatsNewVersion1_6View(onDismiss: onDismiss)
        }
    }
}
