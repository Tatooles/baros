import SwiftUI

struct AccountSignInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("Sign in")
            } icon: {
                Image(systemName: "person.crop.circle.badge.plus")
            }
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(AppTheme.accentGradient)
            .foregroundStyle(AppTheme.onAccent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
