import Foundation

final class AppDependencyContainer {

    // MARK: - Speech
    let speechManager: SpeechManager
    let speechRecognitionManager: SpeechRecognitionManager

    // MARK: - Timer
    let gameTimerManager: GameTimerManager

    // MARK: - Core
    let coreDataStack: CoreDataStack

    // MARK: - Utilities
    let bundleDataLoader: BundleDataLoader

    // MARK: - Child
    let childManager: ChildManager

    // MARK: - Analytics
    let analyticsStore: AnalyticsStore

    // MARK: - Reading sub-stores
    let storyRepository:     StoryRepository
    let readingProgressStore: ReadingProgressStore

    // MARK: - Reading facade
    let storyManager:             StoryManager
    let checkpointHistoryManager: CheckpointHistoryManager

    // MARK: - Writing sub-stores
    let writingProgressStore:  WritingProgressStore
    let writingDrawingStore:   WritingDrawingStore
    let writingSessionManager: WritingSessionManager

    // MARK: - Writing facade
    let writingGameplayManager: WritingGameplayManager

    // MARK: - Phonics
    let phonicsGameplayManager: PhonicsGameplayManager
    let phonicsFlowManager:     PhonicsFlowManager

    // MARK: - OCR
    let ocrManager: OCRManager

    // MARK: - Profile
    let profileStore: ProfileStore

    // MARK: - Skip
    let skipManager: SkipManager

    // MARK: - Sync
    let syncService: FirestoreSyncService

    // MARK: - Guided Learning Path
    let learningPathEngine: LearningPathEngine
    let sessionOrchestrator: SessionOrchestrator
    
    // MARK: - Stores
    let streakStore: StreakStore
    
    // MARK: - Init
    init() {
        coreDataStack    = CoreDataStack()
        bundleDataLoader = BundleDataLoader()

        childManager = ChildManager(coreDataStack: coreDataStack)

        analyticsStore = AnalyticsStore(coreDataStack: coreDataStack,
                                        childManager: childManager)

        storyRepository      = StoryRepository(bundleDataLoader: bundleDataLoader)
        readingProgressStore = ReadingProgressStore(coreDataStack: coreDataStack,
                                                     childManager: childManager)

        storyManager = StoryManager(repository: storyRepository,
                                    progressStore: readingProgressStore,
                                    analyticsStore: analyticsStore)

        checkpointHistoryManager = CheckpointHistoryManager(coreDataStack: coreDataStack,
                                                            childManager: childManager)

        writingProgressStore  = WritingProgressStore(coreDataStack: coreDataStack,
                                                     childManager: childManager)
        writingDrawingStore   = WritingDrawingStore()
        writingSessionManager = WritingSessionManager(analyticsStore: analyticsStore,
                                                      childManager: childManager,
                                                      progressStore: writingProgressStore)

        writingGameplayManager = WritingGameplayManager(
            progressStore:  writingProgressStore,
            drawingStore:   writingDrawingStore,
            sessionManager: writingSessionManager
        )
        phonicsGameplayManager = PhonicsGameplayManager(analyticsStore: analyticsStore,
                                                        childManager: childManager)
        // uid for key-scoping: prefer Firebase UID, fall back to CoreData UUID
        let uid = childManager.currentChild.firebaseUID
                  ?? childManager.currentChild.id?.uuidString
                  ?? "unknown"
        phonicsFlowManager = PhonicsFlowManager(uid: uid)
        ocrManager   = OCRManager(childManager: childManager)
        profileStore = ProfileStore()
        skipManager  = SkipManager(uid: uid)

        speechManager            = SpeechManager()
        speechRecognitionManager = SpeechRecognitionManager()
        gameTimerManager         = GameTimerManager(seconds: 30)

        learningPathEngine = LearningPathEngine(analyticsStore: analyticsStore)
        sessionOrchestrator = SessionOrchestrator(engine: learningPathEngine)
        
        streakStore = StreakStore.shared
        
        // Sync service wires together all stores that need cross-device persistence.
        syncService = FirestoreSyncService(
            analyticsStore:           analyticsStore,
            readingProgressStore:     readingProgressStore,
            writingProgressStore:     writingProgressStore,
            checkpointHistoryManager: checkpointHistoryManager,
            childManager:             childManager
        )

        // Wire the sync service back into the stores so they can push
        // changes to Firestore immediately after writing to Core Data.
        analyticsStore.syncService       = syncService
        readingProgressStore.syncService = syncService
        writingProgressStore.syncService = syncService
        childManager.syncService         = syncService
    }

    // MARK: - Injection

    func inject(into vc: LearningPathHostVC) {
        vc.orchestrator             = sessionOrchestrator
        vc.storyManager             = storyManager
        vc.writingGameplayManager   = writingGameplayManager
        vc.analyticsStore           = analyticsStore
        vc.childManager             = childManager
        vc.checkpointHistoryManager = checkpointHistoryManager
        vc.phonicsFlowManager       = phonicsFlowManager
        vc.phonicsGameplayManager   = phonicsGameplayManager
        vc.bundleDataLoader         = bundleDataLoader
        vc.ocrManager               = ocrManager
        vc.speechManager            = speechManager
        vc.speechRecognitionManager = speechRecognitionManager
        vc.gameTimerManager         = gameTimerManager
        vc.profileStore             = profileStore
        vc.skipManager              = skipManager
    }

    // GUIDED LEARNING PATH DISABLED: used when SceneDelegate points to HomeViewController
    func inject(into vc: HomeViewController) {
        vc.storyManager             = storyManager
        vc.writingGameplayManager   = writingGameplayManager
        vc.analyticsStore           = analyticsStore
        vc.childManager             = childManager
        vc.checkpointHistoryManager = checkpointHistoryManager
        vc.phonicsFlowManager       = phonicsFlowManager
        vc.phonicsGameplayManager   = phonicsGameplayManager
        vc.bundleDataLoader         = bundleDataLoader
        vc.ocrManager               = ocrManager
        vc.speechManager            = speechManager
        vc.speechRecognitionManager = speechRecognitionManager
        vc.gameTimerManager         = gameTimerManager
        vc.profileStore             = profileStore
        vc.skipManager              = skipManager
    }

    func inject(into vc: AnalyticsViewController) {
        vc.analyticsStore           = analyticsStore
        vc.checkpointHistoryManager = checkpointHistoryManager
    }

    func inject(into vc: ReadingPreviewViewController) {
        vc.storyManager             = storyManager
        vc.childManager             = childManager
        vc.checkpointHistoryManager = checkpointHistoryManager
        vc.skipManager              = skipManager
    }

    func inject(into vc: UploadsViewController) {
        vc.ocrManager               = ocrManager
        vc.storyManager             = storyManager
        vc.childManager             = childManager
        vc.checkpointHistoryManager = checkpointHistoryManager
        vc.skipManager              = skipManager
    }

    func inject(into vc: SpinWheelViewController) {
        vc.phonicsFlowManager       = phonicsFlowManager
        vc.phonicsGameplayManager   = phonicsGameplayManager
        vc.bundleDataLoader         = bundleDataLoader
        vc.speechManager            = speechManager
        vc.speechRecognitionManager = speechRecognitionManager
        vc.gameTimerManager         = gameTimerManager
    }

    func inject(into vc: ImageLabelReadingViewController) {
        vc.storyManager             = storyManager
        vc.childManager             = childManager
        vc.checkpointHistoryManager = checkpointHistoryManager
        vc.skipManager              = skipManager
    }

    func inject(into vc: LabelReadingViewController) {
        vc.storyManager             = storyManager
        vc.childManager             = childManager
        vc.checkpointHistoryManager = checkpointHistoryManager
        vc.skipManager              = skipManager
    }
}
