import UIKit
import SwiftUI
import Combine

class LearningPathHostVC: UIViewController {
    
    var orchestrator: SessionOrchestrator!
    var storyManager: StoryManager!
    var writingGameplayManager: WritingGameplayManager!
    var analyticsStore: AnalyticsStore!
    var childManager: ChildManager!
    var checkpointHistoryManager: CheckpointHistoryManager!
    var phonicsFlowManager: PhonicsFlowManager!
    var phonicsGameplayManager: PhonicsGameplayManager!
    var bundleDataLoader: BundleDataLoader!
    var ocrManager: OCRManager!
    var speechManager: SpeechManager!
    var speechRecognitionManager: SpeechRecognitionManager!
    var gameTimerManager: GameTimerManager!
    var profileStore: ProfileStore!
    
    private var cancellables = Set<AnyCancellable>()
    private var hostedView: UIHostingController<LearningPathHomeView>?
    
    // MARK: - Dummy IBOutlets for Storyboard Compatibility
    @IBOutlet weak var readingView: UIView!
    @IBOutlet weak var writingView: UIView!
    @IBOutlet weak var phonicsView: UIView!
    @IBOutlet weak var ocrView: UIView!
    @IBOutlet weak var analytics: UIButton!
    @IBOutlet var continueLabel: UILabel!
    @IBOutlet var subContinueLabel: UILabel!
    @IBOutlet var teddyImageView: UIImageView!
    @IBOutlet var chevronButton: UIButton!

    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let homeView = LearningPathHomeView(orchestrator: orchestrator)
        let host = UIHostingController(rootView: homeView)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
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
    }
    
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
            dismissModalsIfAny()
            _ = navigationController?.popToRootViewController(animated: true)
            
        case .inProgress(let module):
            dismissModalsIfAny()
            pushActivity(for: module)
            
        case .transitioning(let from, let to):
            showTransitionCard(from: from, to: to)
            
        case .complete:
            showSessionSummary()
        }
    }
    
    private func dismissModalsIfAny() {
        if presentedViewController != nil {
            dismiss(animated: true, completion: nil)
        }
    }
    
    private func pushActivity(for module: AksharModule) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        
        switch module {
        case .phonics:
            guard let vc = sb.instantiateViewController(withIdentifier: "SpinWheelViewController") as? SpinWheelViewController else { return }
            vc.phonicsFlowManager       = phonicsFlowManager
            vc.phonicsGameplayManager   = phonicsGameplayManager
            vc.bundleDataLoader         = bundleDataLoader
            vc.speechManager            = speechManager
            vc.speechRecognitionManager = speechRecognitionManager
            vc.gameTimerManager         = gameTimerManager
            vc.orchestrator             = orchestrator
            navigationController?.pushViewController(vc, animated: true)
            
        case .writing:
            guard let previewVC = sb.instantiateViewController(withIdentifier: "WritingPreviewVC") as? WritingPreviewViewController else { return }
            previewVC.writingGameplayManager = writingGameplayManager
            previewVC.orchestrator = orchestrator
            let newStack = previewVC.buildDeepLinkStack(startingWith: [self, previewVC])
            
            // Inject orchestrator into the trace VC dynamically
            if let traceVC = newStack.last {
                // In Swift, we could use a protocol like `AksharActivityDelegate` or just KVC if we expose it to objc, 
                // but we will just add the property directly to all trace VCs in a later step.
                // For now, we will assume trace VCs can be accessed dynamically or we inject it when we modify them.
                // It's cleaner to inject it in WritingPreviewViewController's buildDeepLinkStack or prepareForSegue.
                // Let's rely on WritingPreviewViewController to inject it into trace VCs since it creates them.
            }
            navigationController?.setViewControllers(newStack, animated: true)
            
        case .reading:
            guard let (story, pageIndex, _) = storyManager.getLastActiveStory() else {
                guard let previewVC = sb.instantiateViewController(withIdentifier: "ReadingPreviewVC") as? ReadingPreviewViewController else { return }
                previewVC.storyManager             = storyManager
                previewVC.childManager             = childManager
                previewVC.checkpointHistoryManager = checkpointHistoryManager
                navigationController?.pushViewController(previewVC, animated: true)
                return
            }
            
            guard let previewVC = sb.instantiateViewController(withIdentifier: "ReadingPreviewVC") as? ReadingPreviewViewController else { return }
            previewVC.storyManager             = storyManager
            previewVC.childManager             = childManager
            previewVC.checkpointHistoryManager = checkpointHistoryManager
            
            let pageContent = story.content[pageIndex]
            let targetVC: UIViewController
            
            if let imgName = pageContent.imageURL, !imgName.isEmpty {
                guard let vc = sb.instantiateViewController(withIdentifier: "ImageLabelReadingVC") as? ImageLabelReadingViewController else { return }
                vc.story                    = story
                vc.currentIndex             = pageIndex
                vc.storyTextString          = pageContent.text
                vc.imageName                = imgName
                vc.storyManager             = storyManager
                vc.childManager             = childManager
                vc.checkpointHistoryManager = checkpointHistoryManager
                vc.orchestrator             = orchestrator
                targetVC = vc
            } else {
                guard let vc = sb.instantiateViewController(withIdentifier: "LabelReadingVC") as? LabelReadingViewController else { return }
                vc.story                    = story
                vc.currentIndex             = pageIndex
                vc.storyTextString          = pageContent.text
                vc.storyManager             = storyManager
                vc.childManager             = childManager
                vc.checkpointHistoryManager = checkpointHistoryManager
                vc.orchestrator             = orchestrator
                targetVC = vc
            }
            navigationController?.setViewControllers([self, previewVC, targetVC], animated: true)
        }
    }
    
    private func showTransitionCard(from: AksharModule, to: AksharModule) {
        let transitionView = SessionTransitionView(orchestrator: orchestrator, completedModule: from, nextModule: to)
        let host = UIHostingController(rootView: transitionView)
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = .clear
        present(host, animated: true, completion: nil)
    }
    
    private func showSessionSummary() {
        let summaryView = SessionSummaryView(orchestrator: orchestrator)
        let host = UIHostingController(rootView: summaryView)
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = .clear
        present(host, animated: true, completion: nil)
    }
}
