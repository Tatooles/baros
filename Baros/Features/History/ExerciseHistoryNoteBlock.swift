import SwiftUI

struct ExerciseHistoryNoteBlock: View {
    let note: String
    var presentation: ExerciseHistoryPresentation = .card

    var body: some View {
        if let displayNote = Self.displayNote(from: note) {
            VStack(alignment: .leading, spacing: 8) {
                if presentation == .card {
                    Divider()
                        .overlay(AppTheme.subtleBorder)
                        .accessibilityHidden(true)
                }

                Group {
                    if presentation == .openJournal {
                        Label(displayNote, systemImage: "note.text")
                    } else {
                        Text(displayNote)
                    }
                }
                    .font(presentation == .openJournal ? .footnote : .subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Exercise note")
                    .accessibilityValue(displayNote)
                    .accessibilityIdentifier("ExerciseHistoryNoteText")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    static func displayNote(from note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : note
    }
}
