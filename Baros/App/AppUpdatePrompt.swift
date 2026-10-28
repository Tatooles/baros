import SwiftUI
import UIKit

/// Only the app shell decides idle eligibility. The anchor additionally checks UIKit's
/// actual presentation tree so nested feature/SDK modals need no new global state.
struct AppUpdatePrompt: ViewModifier {
    let isIdle: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var service = AppUpdateService.live()
    @State private var anchor = UpdatePresentationAnchor()
    @State private var presentedOffer: AppUpdateOffer?

    func body(content: Content) -> some View {
        content
            .background { UpdatePresentationProbe(anchor: anchor).frame(width: 0, height: 0) }
            .task(id: scenePhase) {
                if scenePhase == .active { await service.check() }
            }
            .onChange(of: isIdle) { _, idle in
                if !idle { presentedOffer = nil }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { presentedOffer = nil }
            }
            .onChange(of: service.offer) { _, offer in
                if offer == nil { presentedOffer = nil }
            }
            .task(id: canOffer) {
                guard canOffer else { return }
                // Give launch/navigation/dismissal transitions time to settle. Poll only
                // while a deferred offer exists; all state is rechecked after suspension.
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard canOffer, let offer = service.offer else { return }
                    if anchor.isUnobstructed {
                        presentedOffer = offer
                        return
                    }
                }
            }
            .alert("Update available", isPresented: Binding(
                get: { presentedOffer != nil },
                set: { if !$0 { presentedOffer = nil } }
            ), presenting: presentedOffer) { offer in
                Button("Update") {
                    service.didChooseUpdate()
                    openURL(offer.url)
                }
                Button("Later", role: .cancel) { service.later(offer) }
            } message: { offer in
                Text("Baros \(offer.version) is available on the App Store.")
            }
    }

    private var canOffer: Bool {
        isIdle && scenePhase == .active && service.offer != nil && presentedOffer == nil
    }
}

@MainActor
private final class UpdatePresentationAnchor {
    weak var view: UIView?
    var isUnobstructed: Bool {
        guard let window = view?.window, window.isKeyWindow,
              let root = window.rootViewController else { return false }
        func isIdle(_ controller: UIViewController) -> Bool {
            controller.presentedViewController == nil && !controller.isBeingPresented
                && !controller.isBeingDismissed && controller.transitionCoordinator == nil
                && controller.children.allSatisfy(isIdle)
        }
        return isIdle(root)
    }
}

private struct UpdatePresentationProbe: UIViewRepresentable {
    let anchor: UpdatePresentationAnchor
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        anchor.view = view
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { anchor.view = uiView }
}
