import SwiftUI

struct ExerciseHistoryNoteBlock: View {
    let note: String

    var body: some View {
        if let displayNote = Self.displayNote(from: note) {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                    .overlay(AppTheme.subtleBorder)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Exercise Notes")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityIdentifier("ExerciseHistoryNoteLabel")
                    Text(displayNote)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ExerciseHistoryNoteText")
                }
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
