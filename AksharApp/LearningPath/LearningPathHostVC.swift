import UIKit
import SwiftUI
import Combine

class LearningPathHostVC: HomeViewController {

    // ─── TEMPORARY DISABLE FLAG ──────────────────────────────────────────────
    // Set to false to bypass the guided learning path and show the normal home
    // screen. Set back to true when you want the learning path re-enabled.
    static let guidedLearningPathEnabled = true
    // ─────────────────────────────────────────────────────────────────────────

    var orchestrator: SessionOrchestrator!

    private var cancellables = Set<AnyCancellable>()
    private var hostedView: UIHostingController<LearningPathHomeView>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        guard Self.guidedLearningPathEnabled else { return }

        let homeView = LearningPathHomeView(
            orchestrator: orchestrator,
            onExitTapped: { [weak self] in self?.showExitAlert() }
        )
        let host = UIHostingController(rootView: homeView)
        host.view.backgroundColor = .clear

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)

        // Pin to the view edges (NOT safe-area) so the background is truly full-bleed
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        hostedView = host

        if orchestrator.todaysPlan == nil {
            orchestrator.buildDailyPlan()
        }

        setupBindings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)

        guard Self.guidedLearningPathEnabled else { return }

        // If user pressed the back button inside an activity, the phase will still
        // be .inProgress. Reset it to .previewing so they see the "Continue with X"
        // card again rather than a blank home state.
        if case .inProgress(let module) = orchestrator.phase {
            orchestrator.phase = .previewing(module)
        }
    }

    // MARK: - Phase Bindings

    private func setupBindings() {
        orchestrator.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handle(phase)
            }
            .store(in: &cancellables)
    }

    private func handle(_ phase: SessionPhase) {
        switch phase {

        case .idle:
            if presentedViewController != nil {
                dismiss(animated: true) { [weak self] in
                    _ = self?.navigationController?.popToRootViewController(animated: true)
                }
            } else {
                _ = navigationController?.popToRootViewController(animated: true)
            }

        case .previewing(let module):
            let isFirst = orchestrator.completedModules.isEmpty
            showPreview(for: module, isFirst: isFirst)

        case .inProgress(let module):
            // Dismiss the preview modal then push into the real activity
            if presentedViewController != nil {
                dismiss(animated: true) { [weak self] in
                    self?.pushActivity(for: module)
                }
            } else {
                pushActivity(for: module)
            }

        case .transitioning(let from, let to):
            showCompletionAlert(for: from, nextModule: to)

        case .complete:
            showSessionSummary()
        }
    }

    // MARK: - Present helpers

    private func showPreview(for module: AksharModule, isFirst: Bool) {
        let previewView = LearningPathPreviewView(
            orchestrator: orchestrator,
            module: module,
            isFirst: isFirst,
            onExitTapped: { [weak self] in self?.showExitAlert() }
        )
        let host = UIHostingController(rootView: previewView)
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle   = .crossDissolve
        host.view.backgroundColor   = .clear

        swapModal(to: host)
    }

    private func showCompletionAlert(for completed: AksharModule, nextModule: AksharModule) {
        let sb = UIStoryboard(name: "Reading", bundle: nil)
        guard let alertVC = sb.instantiateViewController(withIdentifier: "CustomAlertVC")
                as? CustomAlertViewController else { return }

        alertVC.alertTitle   = "\(completed.name) done!"
        alertVC.alertMessage = completed.completionMessage
        alertVC.buttonText   = "Keep going!"
        alertVC.alertImage   = UIImage(named: "happy_teddy")
        alertVC.modalPresentationStyle = .overFullScreen
        alertVC.modalTransitionStyle   = .crossDissolve

        alertVC.onDismiss = { [weak self] in
            self?.orchestrator.confirmTransition()   // → .previewing(nextModule)
        }

        swapModal(to: alertVC)
    }

    private func showExitAlert() {
        let sb = UIStoryboard(name: "Reading", bundle: nil)
        guard let alertVC = sb.instantiateViewController(withIdentifier: "CustomAlertVC")
                as? CustomAlertViewController else { return }

        alertVC.alertTitle   = "Leaving so soon?"
        alertVC.alertMessage = "Your progress for this session will be lost."
        alertVC.buttonText   = "Exit"
        alertVC.alertImage   = UIImage(named: "sad_teddy")
        alertVC.modalPresentationStyle = .overFullScreen
        alertVC.modalTransitionStyle   = .crossDissolve

        // "Exit" button → leave guided mode and show the real HomeViewController
        alertVC.onDismiss = { [weak self] in
            guard let self else { return }
            _ = self.navigationController?.popToRootViewController(animated: false)
            self.hostedView?.willMove(toParent: nil)
            self.hostedView?.view.removeFromSuperview()
            self.hostedView?.removeFromParent()
            self.hostedView = nil
            self.orchestrator.buildDailyPlan()
        }

        // Tap outside the card → cancel exit, resume guided learning (no action)
        alertVC.onBackgroundTap = { /* do nothing — alert is already dismissed */ }

        swapModal(to: alertVC)
    }

    private func showSessionSummary() {
        let summaryView = SessionSummaryView(orchestrator: orchestrator)
        let host = UIHostingController(rootView: summaryView)
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle   = .crossDissolve
        host.view.backgroundColor   = .clear

        swapModal(to: host)
    }

    /// Swap the currently presented modal with a new one, or present fresh.
    private func swapModal(to new: UIViewController) {
        if let existing = presentedViewController {
            existing.dismiss(animated: false) { [weak self] in
                self?.present(new, animated: true)
            }
        } else {
            present(new, animated: true)
        }
    }

    // MARK: - Push activity VCs

    private func pushActivity(for module: AksharModule) {
        let sb = UIStoryboard(name: "Main", bundle: nil)

        switch module {
        case .phonics:
            let phonicsSB = UIStoryboard(name: "Phonics", bundle: nil)
            guard let vc = phonicsSB.instantiateViewController(withIdentifier: "SpinWheelVC")
                    as? SpinWheelViewController else { return }
            vc.phonicsFlowManager       = phonicsFlowManager
            vc.phonicsGameplayManager   = phonicsGameplayManager
            vc.bundleDataLoader         = bundleDataLoader
            vc.speechManager            = speechManager
            vc.speechRecognitionManager = speechRecognitionManager
            vc.gameTimerManager         = gameTimerManager
            vc.orchestrator             = orchestrator
            navigationController?.pushViewController(vc, animated: true)

        case .writing:
            guard let previewVC = sb.instantiateViewController(withIdentifier: "WritingPreviewVC")
                    as? WritingPreviewViewController else { return }
            previewVC.writingGameplayManager = writingGameplayManager
            previewVC.orchestrator           = orchestrator
            let newStack = previewVC.buildDeepLinkStack(startingWith: [self, previewVC])
            navigationController?.setViewControllers(newStack, animated: true)

        case .reading:
            guard let (story, pageIndex, _) = storyManager.getLastActiveStory() else {
                guard let previewVC = sb.instantiateViewController(withIdentifier: "ReadingPreviewVC")
                        as? ReadingPreviewViewController else { return }
                previewVC.storyManager             = storyManager
                previewVC.childManager             = childManager
                previewVC.checkpointHistoryManager = checkpointHistoryManager
                previewVC.orchestrator             = orchestrator   // ← needed so the chosen story's VC gets it
                navigationController?.pushViewController(previewVC, animated: true)
                return
            }

            guard let previewVC = sb.instantiateViewController(withIdentifier: "ReadingPreviewVC")
                    as? ReadingPreviewViewController else { return }
            previewVC.storyManager             = storyManager
            previewVC.childManager             = childManager
            previewVC.checkpointHistoryManager = checkpointHistoryManager
            previewVC.skipManager              = skipManager

            let pageContent = story.content[pageIndex]
            let targetVC: UIViewController

            if let imgName = pageContent.imageURL, !imgName.isEmpty {
                guard let vc = sb.instantiateViewController(withIdentifier: "ImageLabelReadingVC")
                        as? ImageLabelReadingViewController else { return }
                vc.story                    = story
                vc.currentIndex             = pageIndex
                vc.storyTextString          = pageContent.text
                vc.imageName                = imgName
                vc.storyManager             = storyManager
                vc.childManager             = childManager
                vc.checkpointHistoryManager = checkpointHistoryManager
                vc.skipManager              = skipManager
                vc.orchestrator             = orchestrator
                targetVC = vc
            } else {
                guard let vc = sb.instantiateViewController(withIdentifier: "LabelReadingVC")
                        as? LabelReadingViewController else { return }
                vc.story                    = story
                vc.currentIndex             = pageIndex
                vc.storyTextString          = pageContent.text
                vc.storyManager             = storyManager
                vc.childManager             = childManager
                vc.checkpointHistoryManager = checkpointHistoryManager
                vc.skipManager              = skipManager
                vc.orchestrator             = orchestrator
                targetVC = vc
            }
            navigationController?.setViewControllers([self, previewVC, targetVC], animated: true)
        }
    }
}
