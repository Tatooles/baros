import SwiftUI

struct ExerciseHistoryNoteBlock: View {
    let note: String

    var body: some View {
        if let displayNote = Self.displayNote(from: note) {
            Label(displayNote, systemImage: "note.text")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Exercise note")
                .accessibilityValue(displayNote)
                .accessibilityIdentifier("ExerciseHistoryNoteText")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        }
    }

    static func displayNote(from note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : note
    }
}
