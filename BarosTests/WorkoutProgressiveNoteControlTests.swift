import Observation
import SwiftUI
import UIKit
import XCTest
@testable import Baros

@MainActor
final class WorkoutProgressiveNoteControlTests: XCTestCase {
    func testMovingToAnotherFieldReplacesTheOldNoteEditorAndPreservesDraft() async throws {
        try await assertEditorReplacement(afterMovingTo: .weight)
    }

    func testDismissingFocusReplacesTheOldNoteEditorAndPreservesDraft() async throws {
        try await assertEditorReplacement(afterMovingTo: nil)
    }

    private func assertEditorReplacement(afterMovingTo target: Field?) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let model = Model()
        let host = UIHostingController(rootView: NoteHost(model: model))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        model.requestedFocus = .note
        try await waitUntil { self.findEditor(in: host.view)?.isFirstResponder == true }
        let oldEditor = try XCTUnwrap(findEditor(in: host.view))
        oldEditor.selectedRange = NSRange(location: oldEditor.text.utf16.count, length: 0)
        oldEditor.insertText("\nSecond line")
        try await waitUntil { oldEditor.text == "First line\nSecond line" }
        XCTAssertEqual(model.commits, [])

        model.requestedFocus = target
        try await waitUntil { model.commits == ["First line\nSecond line"] }
        try await waitUntil {
            !oldEditor.isDescendant(of: host.view)
        }
        XCTAssertEqual(model.notes, "First line\nSecond line")
        if target == .weight {
            try await waitUntil { self.findWeight(in: host.view)?.isFirstResponder == true }
        } else {
            XCTAssertFalse(findWeight(in: host.view)?.isFirstResponder ?? false)
            XCTAssertFalse(findEditor(in: host.view)?.isFirstResponder ?? false)
        }

        model.requestedFocus = .note
        try await waitUntil { self.findEditor(in: host.view)?.isFirstResponder == true }
        let newEditor = try XCTUnwrap(findEditor(in: host.view))
        XCTAssertFalse(newEditor === oldEditor)
        XCTAssertEqual(newEditor.text, "First line\nSecond line")
        XCTAssertEqual(model.commits.count, 1, "Replacing the editor must not commit the draft twice.")
    }

    private func findEditor(in view: UIView) -> UITextView? {
        if let editor = view as? UITextView { return editor }
        return view.subviews.lazy.compactMap { self.findEditor(in: $0) }.first
    }

    private func findWeight(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        return view.subviews.lazy.compactMap { self.findWeight(in: $0) }.first
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "The note editor did not reach the expected state.")
    }

    enum Field: Hashable { case note, weight }

    @Observable
    final class Model {
        var notes = "First line"
        var revealed = true
        var requestedFocus: Field?
        var commits: [String] = []
    }

    private struct NoteHost: View {
        @Bindable var model: Model
        @FocusState private var focusedField: Field?
        @State private var weight = ""

        var body: some View {
            VStack {
                WorkoutProgressiveNoteControl(
                    notes: $model.notes,
                    addTitle: "Add note",
                    addSystemImage: "note.text",
                    placeholder: "Note",
                    accessibilityLabel: "Note",
                    addAccessibilityIdentifier: "AddNote",
                    fieldAccessibilityIdentifier: "Note",
                    addAccessibilityHint: nil,
                    addButtonHorizontalPadding: 0,
                    focusTarget: Field.note,
                    isRevealed: $model.revealed,
                    focusedField: $focusedField,
                    commitOnFocusLoss: {
                        model.commits.append($0)
                        model.notes = $0
                    }
                )
                TextField("Weight", text: $weight)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .weight)
            }
            .onChange(of: model.requestedFocus, initial: true) { _, target in
                focusedField = target
            }
        }
    }
}
