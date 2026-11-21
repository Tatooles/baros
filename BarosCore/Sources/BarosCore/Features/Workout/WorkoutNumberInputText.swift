public struct WorkoutNumberInputText {
    public init() {}

    private var draft: String?

    var draftText: String? {
        draft
    }

    public mutating func updateDraft(_ value: String, isFocused: Bool = true) {
        guard !(value.isEmpty && !isFocused) else { return }
        draft = value
    }

    public mutating func endEditing() {
        draft = nil
    }

    public func displayText(fallback: @autoclosure () -> String) -> String {
        draft ?? fallback()
    }

    public func displayText(for value: Double?) -> String {
        displayText(fallback: value.map(WorkoutFormatters.number) ?? "")
    }
}
