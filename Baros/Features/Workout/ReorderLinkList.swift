import BarosCore
import SwiftUI

struct ReorderLinkList<Item: ReorderListExercise, Header: View>: View {
    private static var cardSpacing: CGFloat { 12 }
    private static var linkDiameter: CGFloat { 30 }
    private static var linkTapSize: CGSize { CGSize(width: 64, height: 44) }
    private static var railLeadingInset: CGFloat { 4 }

    let exercises: [Item]
    let regroup: ([UUID?]) -> Void
    let finish: () -> Void
    let header: Header
    let memory: ReorderListMemory
    @State private var scrollPosition: ScrollPosition
    @State private var labelSpace: LabelSpace

    init(
        exercises: [Item],
        regroup: @escaping ([UUID?]) -> Void,
        finish: @escaping () -> Void,
        header: Header,
        memory: ReorderListMemory
    ) {
        self.exercises = exercises
        self.regroup = regroup
        self.finish = finish
        self.header = header
        self.memory = memory
        _scrollPosition = State(initialValue: ScrollPosition(y: memory.offset))
        _labelSpace = State(initialValue: LabelSpace(exercises))
    }

    private struct LabelSpace {
        var above: Set<UUID> = []
        var below: Set<UUID> = []

        init(_ exercises: [Item]) {
            for block in SupersetGrouping.blocks(exercises, groupID: \.supersetGroupID) where block.isSuperset {
                if let first = block.members.first { above.insert(first.id) }
                if let last = block.members.last { below.insert(last.id) }
            }
        }
    }

    var body: some View {
        let groupIDs = exercises.map(\.supersetGroupID)
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    if index == 0 {
                        Color.clear.frame(height: Self.cardSpacing / 2)
                        if labelSpace.above.contains(exercise.id) { emptyLabel(.bottom) }
                    }
                    ReorderExerciseRow(exercise: exercise)
                        .padding(cardInsets(for: exercise))
                        .background(alignment: .leading) { railPiece(at: index, groupIDs: groupIDs) }
                    if index < exercises.count - 1 {
                        gap(below: index, groupIDs: groupIDs)
                    } else {
                        if labelSpace.below.contains(exercise.id) { emptyLabel(.top) }
                        Color.clear.frame(height: Self.cardSpacing / 2)
                    }
                }
            }
            .padding(.top, 8)
        }
        .scrollPosition($scrollPosition)
        .rememberingScrollOffset(in: memory)
        .safeAreaBar(edge: .bottom, spacing: 0) { bar }
        .navigationSubtitle("Tap a link to join or split")
    }

    private func cardInsets(for exercise: Item) -> EdgeInsets {
        let list = memory.listFrame
        guard let card = memory.cardFrames[exercise.id] ?? memory.cardFrames.values.first else {
            return EdgeInsets(top: 0, leading: 48, bottom: 0, trailing: 54)
        }
        return EdgeInsets(top: 0, leading: card.minX - list.minX, bottom: 0, trailing: list.maxX - card.maxX)
    }

    private func emptyLabel(_ spacingEdge: Edge.Set) -> some View {
        SupersetLabel(count: 2)
            .hidden()
            .accessibilityHidden(true)
            .padding(spacingEdge, SupersetRail<EmptyView>.labelSpacing)
    }

    private func gap(below upper: Int, groupIDs: [UUID?]) -> some View {
        VStack(spacing: 0) {
            if labelSpace.below.contains(exercises[upper].id) { emptyLabel(.top) }
            Color.clear.frame(height: Self.cardSpacing)
            if labelSpace.above.contains(exercises[upper + 1].id) { emptyLabel(.bottom) }
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .leading) {
            rail(joinsAbove: true, joinsBelow: true, isVisible: SupersetGrouping.areGrouped(groupIDs, upper, upper + 1))
        }
        .overlay { link(below: upper, groupIDs: groupIDs) }
        .zIndex(1)
    }

    private func railPiece(at index: Int, groupIDs: [UUID?]) -> some View {
        let joinsAbove = SupersetGrouping.areGrouped(groupIDs, index, index - 1)
        let joinsBelow = SupersetGrouping.areGrouped(groupIDs, index, index + 1)
        return rail(joinsAbove: joinsAbove, joinsBelow: joinsBelow, isVisible: joinsAbove || joinsBelow)
    }

    private func rail(joinsAbove: Bool, joinsBelow: Bool, isVisible: Bool) -> some View {
        let radius = SupersetRail<EmptyView>.railWidth / 2
        return UnevenRoundedRectangle(
            topLeadingRadius: joinsAbove ? 0 : radius,
            bottomLeadingRadius: joinsBelow ? 0 : radius,
            bottomTrailingRadius: joinsBelow ? 0 : radius,
            topTrailingRadius: joinsAbove ? 0 : radius
        )
        .fill(isVisible ? AppTheme.brandAccentForeground : .clear)
        .frame(width: SupersetRail<EmptyView>.railWidth)
        .padding(.leading, Self.railLeadingInset)
        .accessibilityHidden(true)
    }

    private func link(below upper: Int, groupIDs: [UUID?]) -> some View {
        let isLinked = SupersetGrouping.areGrouped(groupIDs, upper, upper + 1)
        let names = "\(exercises[upper].name) and \(exercises[upper + 1].name)"
        return Button {
            withAnimation(.snappy) { regroup(SupersetGrouping.togglingLink(groupIDs, below: upper)) }
        } label: {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isLinked ? AppTheme.onBrandAccent : AppTheme.textSecondary)
                .frame(width: Self.linkDiameter, height: Self.linkDiameter)
                .background(isLinked ? AppTheme.brandAccentFill : AppTheme.canvasBackground, in: Circle())
                .overlay(Circle().stroke(isLinked ? Color.clear : AppTheme.subtleBorder))
                .frame(width: Self.linkTapSize.width, height: Self.linkTapSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLinked ? "Unlink \(names)" : "Link \(names)")
        .accessibilityAddTraits(isLinked ? .isSelected : [])
        .accessibilityIdentifier("SupersetLinkButton-\(upper)")
    }

    private var bar: some View {
        Button(action: finish) {
            Text("Done Linking")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(AppTheme.brandAccentFill)
        .font(.headline)
        .controlSize(.large)
        .accessibilityIdentifier("DoneLinkingButton")
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}
