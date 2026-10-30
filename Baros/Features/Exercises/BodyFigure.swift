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

    /// Scales the figure to fit `size`, centered.
    func transform(fitting size: CGSize) -> CGAffineTransform {
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let offsetX = (size.width - bounds.width * scale) / 2
        let offsetY = (size.height - bounds.height * scale) / 2
        return CGAffineTransform(translationX: offsetX, y: offsetY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)
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
