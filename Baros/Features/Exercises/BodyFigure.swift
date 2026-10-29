import SwiftUI

/// A drawn region of the body figure. Muscle regions map to the exercise
/// muscle group they select; the rest only complete the silhouette.
enum BodyFigurePart: String, CaseIterable, Sendable {
    case abs
    case adductors
    case ankles
    case biceps
    case calves
    case chest
    case deltoids
    case feet
    case forearm
    case gluteal
    case gluteusMedius
    case hair
    case hamstring
    case hands
    case head
    case knees
    case lats
    case lowerBack
    case neck
    case obliques
    case quadriceps
    case tibialis
    case trapezius
    case triceps
    case upperBack

    var muscleGroup: ExerciseMuscleGroup? {
        switch self {
        case .abs, .obliques: return .core
        case .adductors: return .adductors
        case .biceps: return .biceps
        case .calves: return .calves
        case .chest: return .chest
        case .deltoids: return .shoulders
        case .forearm: return .forearms
        case .gluteal: return .glutes
        case .gluteusMedius: return .abductors
        case .hamstring: return .hamstrings
        case .lats: return .lats
        case .lowerBack: return .lowerBack
        case .neck: return .neck
        case .quadriceps: return .quads
        case .trapezius: return .traps
        case .triceps: return .triceps
        case .upperBack: return .upperBack
        case .ankles, .feet, .hair, .hands, .head, .knees, .tibialis: return nil
        }
    }
}

extension ExerciseMuscleGroup {
    /// The figure regions highlighted for this group. Full Body highlights every
    /// muscle, Upper Body everything above the waist, and Lower Body the hips
    /// and legs; Cardio and Other have no anatomical region.
    var figureParts: Set<BodyFigurePart> {
        let groups: Set<ExerciseMuscleGroup> = switch self {
        case .fullBody: Self.upperBodyGroups.union(Self.lowerBodyGroups)
        case .upperBody: Self.upperBodyGroups
        case .lowerBody: Self.lowerBodyGroups
        default: [self]
        }
        return Set(BodyFigurePart.allCases.filter { $0.muscleGroup.map(groups.contains) == true })
    }

    private static let upperBodyGroups: Set<ExerciseMuscleGroup> = [
        .neck, .traps, .shoulders, .chest, .upperBack, .lats, .core, .lowerBack,
        .biceps, .triceps, .forearms,
    ]
    private static let lowerBodyGroups: Set<ExerciseMuscleGroup> = [
        .glutes, .abductors, .adductors, .quads, .hamstrings, .calves,
    ]
}

enum BodyFigureSide: Hashable, CaseIterable, Sendable {
    case front
    case back

    var drawing: BodyFigureDrawing {
        switch self {
        case .front: return .frontArtwork
        case .back: return .backArtwork
        }
    }

    var title: String {
        switch self {
        case .front: return "Front"
        case .back: return "Back"
        }
    }

    /// The side to show for `group`: stays on `current` when it draws the group
    /// (or the group has no region), otherwise turns to the side that does.
    static func showing(_ group: ExerciseMuscleGroup, from current: BodyFigureSide) -> BodyFigureSide {
        let parts = group.figureParts
        guard !parts.isEmpty, !current.drawing.draws(parts) else { return current }
        return allCases.first { $0.drawing.draws(parts) } ?? current
    }
}

struct BodyFigureRegionArtwork: Sendable {
    let part: BodyFigurePart
    let paths: [String]
}

struct BodyFigureRegion: Identifiable, Sendable {
    let part: BodyFigurePart
    let path: Path

    var id: BodyFigurePart { part }
}

/// One side of the body figure in its source coordinate space.
struct BodyFigureDrawing: Sendable {
    let bounds: CGRect
    let regions: [BodyFigureRegion]

    init(bounds: CGRect, regions: [BodyFigureRegionArtwork]) {
        self.bounds = bounds
        var merged: [BodyFigurePart: Path] = [:]
        var order: [BodyFigurePart] = []
        for region in regions {
            if merged[region.part] == nil { order.append(region.part) }
            var path = merged[region.part] ?? Path()
            for data in region.paths {
                path.addPath(SVGPathData.path(from: data))
            }
            merged[region.part] = path
        }
        self.regions = order.map { BodyFigureRegion(part: $0, path: merged[$0]!) }
    }

    func draws(_ parts: Set<BodyFigurePart>) -> Bool {
        regions.contains { parts.contains($0.part) }
    }

    /// Scales the figure to fit `size`, centered.
    func transform(fitting size: CGSize) -> CGAffineTransform {
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let offsetX = (size.width - bounds.width * scale) / 2
        let offsetY = (size.height - bounds.height * scale) / 2
        return CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)
    }

    /// The muscle group under `point` in a figure drawn at `size`. Small muscles
    /// such as forearms are only a few points wide, so a miss falls back to the
    /// nearest muscle within `tolerance` points.
    func muscleGroup(at point: CGPoint, in size: CGSize, tolerance: CGFloat = 18) -> ExerciseMuscleGroup? {
        let transform = transform(fitting: size)
        let figurePoint = point.applying(transform.inverted())
        let scale = transform.a
        let muscles = regions.filter { $0.part.muscleGroup != nil }

        if let hit = muscles.last(where: { $0.path.contains(figurePoint) }) {
            return hit.part.muscleGroup
        }

        let ringCount = 3
        let samplesPerRing = 16
        for ring in 1...ringCount {
            let radius = tolerance / scale * CGFloat(ring) / CGFloat(ringCount)
            var hits: [BodyFigurePart: Int] = [:]
            for sample in 0..<samplesPerRing {
                let angle = CGFloat(sample) / CGFloat(samplesPerRing) * 2 * .pi
                let probe = CGPoint(x: figurePoint.x + cos(angle) * radius, y: figurePoint.y + sin(angle) * radius)
                if let hit = muscles.last(where: { $0.path.contains(probe) }) {
                    hits[hit.part, default: 0] += 1
                }
            }
            if let best = hits.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key.rawValue > $1.key.rawValue) }) {
                return best.key.muscleGroup
            }
        }
        return nil
    }
}

/// Parses the absolute M/L/C/Q/Z path data in `BodyFigureArtwork`.
enum SVGPathData {
    static func path(from data: String) -> Path {
        var path = Path()
        var command: Character?
        var operands: [CGFloat] = []
        var number = ""

        func endNumber() {
            if let value = Double(number) { operands.append(CGFloat(value)) }
            number = ""
        }

        func point(_ index: Int) -> CGPoint {
            CGPoint(x: operands[index], y: operands[index + 1])
        }

        func applyCommand() {
            switch command {
            case "M" where operands.count == 2:
                path.move(to: point(0))
            case "L" where operands.count == 2:
                path.addLine(to: point(0))
            case "C" where operands.count == 6:
                path.addCurve(to: point(4), control1: point(0), control2: point(2))
            case "Q" where operands.count == 4:
                path.addQuadCurve(to: point(2), control: point(0))
            case "Z":
                path.closeSubpath()
            default:
                break
            }
        }

        for character in data {
            if character.isLetter {
                endNumber()
                applyCommand()
                command = character
                operands = []
            } else if character == " " || character == "," {
                endNumber()
            } else if character == "-", !number.isEmpty {
                endNumber()
                number = "-"
            } else {
                number.append(character)
            }
        }
        endNumber()
        applyCommand()
        return path
    }
}
