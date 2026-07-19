import SwiftUI

enum DeleteDataMode {
    case account
    case localData

    var navigationTitle: String {
        switch self {
        case .account:
            "Delete Account"
        case .localData:
            "Delete Local Data"
        }
    }

    var warningText: String {
        switch self {
        case .account:
            "This permanently deletes your cloud account, cloud workout data, and local data on this iPhone."
        case .localData:
            "This deletes only local data on this iPhone. It does not delete a cloud account or cloud data."
        }
    }

    var buttonTitle: String {
        switch self {
        case .account:
            "Delete Account"
        case .localData:
            "Delete Local Data"
        }
    }
}

struct DeleteDataConfirmationView: View {
    @StateObject private var coordinator: AccountDeletionCoordinator
    @Environment(\.dismiss) private var dismiss

    let mode: DeleteDataMode
    let onCompleted: () -> Void
    @State private var confirmationText = ""

    init(
        mode: DeleteDataMode,
        coordinator: AccountDeletionCoordinator,
        onCompleted: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.onCompleted = onCompleted
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.red)

                    Text(mode.warningText)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Type DELETE to continue", text: $confirmationText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("DeleteDataConfirmationField")
                }
                .padding(.vertical, 6)
            }

            if case .failed(let message) = coordinator.phase {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("DeleteDataErrorMessage")
                }
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        switch mode {
                        case .account:
                            await coordinator.deleteAccount()
                        case .localData:
                            await coordinator.deleteLocalData()
                        }
                    }
                } label: {
                    HStack {
                        Text(buttonText)
                        if coordinator.phase.isRunning {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(confirmationText != "DELETE" || coordinator.phase.isRunning)
                .accessibilityIdentifier("DeleteDataConfirmButton")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .navigationTitle(mode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(coordinator.phase.isRunning)
        .onChange(of: coordinator.phase) { _, phase in
            if phase == .completed {
                onCompleted()
                dismiss()
            }
        }
    }

    private var buttonText: String {
        switch coordinator.phase {
        case .deletingCloudData:
            "Deleting Cloud Data..."
        case .deletingAccount:
            "Deleting Account..."
        case .clearingLocalData:
            "Clearing Local Data..."
        case .idle, .completed, .failed:
            mode.buttonTitle
        }
    }
}
