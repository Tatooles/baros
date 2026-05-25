import SwiftUI

struct SurfaceCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder var content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                    .stroke(AppTheme.border)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }
}
