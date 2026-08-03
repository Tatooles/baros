import SwiftUI

/// Resolves the release catalog's stable sheet identifier to its native
/// SwiftUI implementation. Each release sheet owns its layout and styling.
struct WhatsNewSheet: View {
    let sheetID: WhatsNewSheetID
    let onDismiss: () -> Void

    @ViewBuilder
    var body: some View {
        switch sheetID {
        case .version1_0:
            WhatsNewVersion1_0View(onDismiss: onDismiss)
        }
    }
}
