import SwiftUI

struct ExerciseHistoryNoteBlock: View {
    let note: String

    var body: some View {
        if let displayNote = Self.displayNote(from: note) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Exercise Notes")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(displayNote)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    static func displayNote(from note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : note
    }
}
