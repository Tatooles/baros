import SwiftUI

/// Front and back body figures that highlight the selected target area. The
/// figure only shows the selection; choosing happens in the labeled picker
/// above it. VoiceOver reads it as a single image.
struct MuscleFigureView: View {
    let selection: ExerciseMuscleGroup

    var body: some View {
        HStack(spacing: 24) {
            BodyFigureSideView(drawing: .frontArtwork, highlighted: selection.figureParts)
            BodyFigureSideView(drawing: .backArtwork, highlighted: selection.figureParts)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .animation(.easeOut(duration: 0.18), value: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body figure")
        .accessibilityValue(
            selection.figureParts.isEmpty ? "No muscles highlighted" : "\(selection.displayName) highlighted"
        )
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("ExerciseMuscleFigure")
    }
}

private struct BodyFigureSideView: View {
    @Environment(\.colorSchemeContrast) private var contrast

    let drawing: BodyFigureDrawing
    let highlighted: Set<BodyFigurePart>

    var body: some View {
        GeometryReader { proxy in
            let transform = drawing.transform(fitting: proxy.size)
            ZStack {
                ForEach(drawing.regions) { region in
                    let path = region.path.applying(transform)
                    path.fill(fill(for: region.part))
                    if contrast == .increased {
                        path.stroke(AppTheme.textSecondary, lineWidth: 0.5)
                    }
                }
            }
        }
        .aspectRatio(drawing.bounds.size, contentMode: .fit)
    }

    private func fill(for part: BodyFigurePart) -> Color {
        if highlighted.contains(part) { return AppTheme.brandAccentFill }
        return part.muscleGroup == nil ? Self.silhouetteFill : Self.muscleFill
    }

    private static let muscleFill = BarosAdaptiveColor.dynamic(light: 0xD5D6DC, dark: 0x3A3B40)
    private static let silhouetteFill = BarosAdaptiveColor.dynamic(light: 0xE9E9ED, dark: 0x2A2B2F)
}
