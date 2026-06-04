import Foundation
import Combine

enum AksharModule: String, CaseIterable {
    case phonics
    case writing
    case reading
    
    var name: String {
        switch self {
        case .phonics: return "Phonics"
        case .writing: return "Writing"
        case .reading: return "Reading"
        }
    }
}

enum SessionPhase: Equatable {
    case idle
    case previewing(AksharModule)                        // "Begin / Continue with X" card
    case inProgress(AksharModule)                        // inside the actual activity
    case transitioning(from: AksharModule, to: AksharModule)  // completion alert before next preview
    case complete
}

final class SessionOrchestrator: ObservableObject {
    @Published var phase: SessionPhase = .idle
    var todaysPlan: DailyPlan?
    var completedModules: [AksharModule] = []
    
    private var phonicsRoundsCompleted = 0
    private var lettersCompleted = 0
    private var readingPagesCompleted = 0
    
    private let engine: LearningPathEngine
    
    init(engine: LearningPathEngine) {
        self.engine = engine
    }
    
    func buildDailyPlan() {
        self.todaysPlan = engine.buildDailyPlan()
        self.completedModules = []
        self.phonicsRoundsCompleted = 0
        self.lettersCompleted = 0
        self.readingPagesCompleted = 0
        self.phase = .idle
    }
    
    /// Home arrow tapped → show "Begin with X" preview for first module
    func startSession() {
        guard let plan = todaysPlan, let first = plan.order.first else { return }
        phase = .previewing(first)
    }
    
    /// Arrow tapped on "Begin / Continue" card → jump into the real activity
    func beginCurrentModule() {
        guard case .previewing(let module) = phase else { return }
        phase = .inProgress(module)
    }
    
    func recordPhonicsRoundCompleted() {
        guard case .inProgress(let currentModule) = phase, currentModule == .phonics else { return }
        phonicsRoundsCompleted += 1
        if phonicsRoundsCompleted >= 2 {
            completeCurrentModule(currentModule)
        }
    }
    
    func recordLetterCompleted() {
        guard case .inProgress(let currentModule) = phase, currentModule == .writing else { return }
        lettersCompleted += 1
        if lettersCompleted >= 2 {
            completeCurrentModule(currentModule)
        }
    }
    
    func recordReadingPageCompleted() {
        guard case .inProgress(let currentModule) = phase, currentModule == .reading else { return }
        readingPagesCompleted += 1
        if readingPagesCompleted >= 3 {
            completeCurrentModule(currentModule)
        }
    }
    
    private func completeCurrentModule(_ module: AksharModule) {
        completedModules.append(module)
        guard let plan = todaysPlan else { return }
        
        let nextIndex = completedModules.count
        if nextIndex < plan.order.count {
            let nextModule = plan.order[nextIndex]
            phase = .transitioning(from: module, to: nextModule)
        } else {
            phase = .complete
        }
    }
    
    /// Called after the completion alert is dismissed — show preview for next module
    func confirmTransition() {
        guard case .transitioning(_, let toModule) = phase else { return }
        phase = .previewing(toModule)
    }
}
