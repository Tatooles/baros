import SwiftUI

/// PROTOTYPE — Three native iOS 26 accessory treatments for answering whether
/// a full-width workout accessory feels balanced above Baros's three-tab bar.
struct Issue47AccessoryPrototypeView: View {
    private enum Variant: String, CaseIterable, Identifiable {
        case status = "A — Status-rich"
        case quiet = "B — Quiet"
        case baseline = "C — No accessory"

        var id: Self { self }
    }

    private enum PrototypeTab: Hashable {
        case history
        case home
        case profile
    }

    @State private var variant: Variant = .status
    @State private var selectedTab: PrototypeTab = .home

    var body: some View {
        Group {
            if #available(iOS 26.1, *) {
                tabs
                    .tabViewBottomAccessory(isEnabled: variant != .baseline) {
                        accessoryButton
                    }
            } else if variant == .baseline {
                tabs
            } else {
                tabs
                    .tabViewBottomAccessory {
                        accessoryButton
                    }
            }
        }
        .tint(AppTheme.brandAccentForeground)
        .tabBarMinimizeBehavior(.never)
        .overlay(alignment: .top) {
            prototypeSwitcher
                .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            PrototypePage(title: "History", symbol: "clock.arrow.circlepath")
                .tag(PrototypeTab.history)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            HomePrototypeContent()
                .tag(PrototypeTab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }

            PrototypePage(title: "Profile", symbol: "person.crop.circle")
                .tag(PrototypeTab.profile)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }

    private var accessoryButton: some View {
        Button(action: {}) {
            accessoryContent
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Return to workout")
        .accessibilityValue("Upper Body, 38 minutes elapsed, 6 of 12 sets completed")
    }

    @ViewBuilder
    private var accessoryContent: some View {
        switch variant {
        case .status:
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.brandAccentMuted, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Upper Body")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("38 min elapsed")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("6 of 12")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("sets")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, 16)

        case .quiet:
            HStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.brandAccentFill)
                    .frame(width: 7, height: 7)
                Text("Upper Body")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 10)
                Text("38 min")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 18)

        case .baseline:
            EmptyView()
        }
    }

    private var prototypeSwitcher: some View {
        VStack(spacing: 6) {
            Text("ISSUE #47 PROTOTYPE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 12) {
                Button {
                    cycleVariant(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Previous variant")
                .accessibilityIdentifier("PreviousPrototypeVariant")

                Text(variant.rawValue)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)

                Button {
                    cycleVariant(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Next variant")
                .accessibilityIdentifier("NextPrototypeVariant")
            }
            .frame(maxWidth: 360)
        }
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    private func cycleVariant(by offset: Int) {
        let variants = Variant.allCases
        guard let index = variants.firstIndex(of: variant) else { return }
        variant = variants[(index + offset + variants.count) % variants.count]
    }
}

private struct HomePrototypeContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Color.clear.frame(height: 64)

                Text("Home")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 14) {
                    Text("ACTIVE WORKOUT")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Upper Body")
                        .font(.title2.bold())
                    Text("38 min elapsed")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Return to Workout")
                        .font(.headline)
                        .foregroundStyle(AppTheme.onBrandAccent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(AppTheme.brandAccentFill, in: Capsule())
                }
                .padding(18)
                .background(AppTheme.groupedSurface, in: .rect(cornerRadius: AppTheme.cardCornerRadius))

                VStack(alignment: .leading, spacing: 14) {
                    Text("This Week")
                        .font(.headline)
                    HStack {
                        ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                            Text(day)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Text("3 workouts")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(18)
                .background(AppTheme.groupedSurface, in: .rect(cornerRadius: AppTheme.cardCornerRadius))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Workout")
                        .font(.headline)
                    Text("Lower Body")
                        .font(.title3.weight(.semibold))
                    Text("Yesterday · 52 min · 5 exercises")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.groupedSurface, in: .rect(cornerRadius: AppTheme.cardCornerRadius))
            }
            .padding(.horizontal, AppTheme.shellPadding)
            .padding(.bottom, 24)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
    }
}

private struct PrototypePage: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.brandAccentForeground)
            Text(title)
                .font(.largeTitle.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.canvasBackground.ignoresSafeArea())
    }
}
