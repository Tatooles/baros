import SwiftUI

/// A body figure that highlights the selected target area and selects a muscle
/// when tapped. One side shows at a time so muscles stay large enough to tap;
/// choosing a muscle from the list turns the figure to the side that draws it.
/// VoiceOver reads the figure as an image; selection goes through the labeled
/// picker beside it.
struct MuscleFigureView: View {
    @Binding var selection: ExerciseMuscleGroup
    @State private var side: BodyFigureSide
    @State private var tapCount = 0

    init(selection: Binding<ExerciseMuscleGroup>) {
        _selection = selection
        _side = State(initialValue: BodyFigureSide.showing(selection.wrappedValue, from: .front))
    }

    var body: some View {
        VStack(spacing: 16) {
            // The ZStack overlays the outgoing and incoming sides while they crossfade.
            ZStack {
                BodyFigureSideView(drawing: side.drawing, highlighted: selection.figureParts, onSelect: select)
                    .id(side)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 380)
            .animation(.easeOut(duration: 0.18), value: selection)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Body figure")
            .accessibilityValue(
                selection.figureParts.isEmpty ? "No muscles highlighted" : "\(selection.displayName) highlighted"
            )
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("ExerciseMuscleFigure")

            Picker("Figure Side", selection: $side.animation(.easeInOut(duration: 0.22))) {
                ForEach(BodyFigureSide.allCases, id: \.self) { side in
                    Text(side.title).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            .accessibilityIdentifier("ExerciseMuscleFigureSidePicker")
        }
        .sensoryFeedback(.selection, trigger: tapCount)
        .onChange(of: selection) { _, newSelection in
            let newSide = BodyFigureSide.showing(newSelection, from: side)
            guard newSide != side else { return }
            withAnimation(.easeInOut(duration: 0.22)) { side = newSide }
        }
    }

    private func select(_ group: ExerciseMuscleGroup) {
        guard group != selection else { return }
        selection = group
        tapCount += 1
    }
}

private struct BodyFigureSideView: View {
    @Environment(\.colorSchemeContrast) private var contrast

    let drawing: BodyFigureDrawing
    let highlighted: Set<BodyFigurePart>
    let onSelect: (ExerciseMuscleGroup) -> Void

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
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let group = drawing.muscleGroup(at: location, in: proxy.size) {
                    onSelect(group)
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
