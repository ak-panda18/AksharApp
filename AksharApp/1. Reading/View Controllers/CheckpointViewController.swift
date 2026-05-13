// CheckpointViewController.swift — same functionality, debug prints removed

import UIKit
import AVFoundation
import Speech
import AVKit
import os.log
import SwiftUI

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "CheckpointVC")

class CheckpointViewController: UIViewController {

    // MARK: - Analytics
    var readingSession: ReadingSessionData?

    // MARK: - Injected
    var storyManager: StoryManager!
    var childManager: ChildManager!
    var checkpointHistoryManager: CheckpointHistoryManager!

    // MARK: - Outlets
    @IBOutlet weak var videoContainerView: UIView!
    @IBOutlet weak var checkpointLabel: UILabel!
    @IBOutlet weak var micButton: UIButton!
    @IBOutlet weak var instructionLabel: UILabel!
    @IBOutlet weak var previousScoresButton: UIButton!
    @IBOutlet weak var titleView: UIView!
    @IBOutlet weak var backView: UIView!
    @IBOutlet weak var textView: UIView!
    @IBOutlet weak var dialogueView: UIView!
    @IBOutlet weak var skipButton: UIButton!

    // MARK: - Properties
    var story: Story!
    var checkpointItem: CheckpointItem!
    var nextPageIndex: Int = 0
    var fallbackPageIndex: Int = 0
    var forceRetake: Bool = false

    var player: AVPlayer?
    var playerLayer: AVPlayerLayer?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_IN"))
    private let audioEngine      = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var stopTimer: Timer?
    private var currentTranscript: String = ""
    private var attemptCount = 0
    private var originalCheckpointText: String = ""
    private var currentEvaluationText: String = ""
    private var adaptiveRetryTexts: [String] = []
    private let maxAttempts  = 3
    private var hasPerfectScore = false
    private var isPaused        = false
    private var checkpointStartTime: Date?

    // MARK: - Lifecycle
    private func verifyDependencies() {
        assert(storyManager != nil, "storyManager was not injected into \(type(of: self))")
        assert(childManager != nil, "childManager was not injected into \(type(of: self))")
        assert(checkpointHistoryManager != nil, "checkpointHistoryManager was not injected into \(type(of: self))")
        assert(story != nil, "story was not injected into \(type(of: self))")
        assert(checkpointItem != nil, "checkpointItem was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        playVideoInView()

        originalCheckpointText = checkpointItem.text
        currentEvaluationText = checkpointItem.text

        setupUI()
        updatePreviousScoresButtonState()
        updateInstructionText()

        if !forceRetake && isCheckpointCompleted() {
            showCompletedState()
        } else {
            showActiveState()
        }
        
        // Enable skip if user has attempted this checkpoint before (even in a previous session)
        updateSkipButtonState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layer = playerLayer {
            layer.frame        = videoContainerView.bounds
            layer.cornerRadius = videoContainerView.layer.cornerRadius
            layer.masksToBounds = true
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkpointStartTime = Date()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        endReadingSessionIfNeeded()
        hardResetAudio()
    }

    // MARK: - Actions
    @IBAction func previousScoresTapped(_ sender: UIButton) {
        guard let scoresVC = storyboard?.instantiateViewController(
            withIdentifier: "PreviousScoresViewController"
        ) as? PreviousScoresViewController else { return }
        scoresVC.checkpointHistoryManager = checkpointHistoryManager
        scoresVC.originalText             = checkpointItem.text
        scoresVC.storyFont                = checkpointLabel.font ?? UIFont.systemFont(ofSize: 30)
        scoresVC.targetStoryTitle         = story?.title ?? "Unknown Story"
        scoresVC.targetCheckpointNumber   = (fallbackPageIndex + 1)

        if let sheet = scoresVC.sheetPresentationController {
            sheet.detents                = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible  = true
        }
        present(scoresVC, animated: true)
    }

    @IBAction func micTapped(_ sender: UIButton) {
        if hasPerfectScore { goToNextStoryPage(); return }

        if audioEngine.isRunning {
            startGracefulStop()
            playVideoAgain()
        } else {
            stopAndResetVideo()
            startListening()
        }
    }

    @IBAction func backTapped(_ sender: Any) {
        navigationController?.popViewController(animated: false)
    }

    @IBAction func homeTapped(_ sender: UIButton) {
        endReadingSessionIfNeeded()

        if let nav = navigationController {
            if let homeVC = nav.viewControllers.first(where: { $0 is HomeViewController }) {
                nav.popToViewController(homeVC, animated: true)
                return
            }
        }

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootNav = window.rootViewController as? UINavigationController {
            rootNav.dismiss(animated: true)
            rootNav.popToRootViewController(animated: true)
        }
    }

    @IBAction func continueTapped(_ sender: UIButton) {
        goToNextStoryPage()
    }
    
    @IBAction func skipTapped(_ sender: UIButton) {
        // Button is already disabled if no attempts, but double-check
        guard hasAttemptedBefore() else {
            presentCustomAlert(
                title: "Wait!",
                message: "You can't skip yet! You must try reading it at least once. You can do it!",
                buttonText: "I'll Try!",
                image: UIImage(named: "mascot_encouraging")
            ) {}
            return
        }
        
        let skips = SkipManager.shared.availableSkips
        if skips > 0 {
            showSkipTicketAlert(skips: skips)
        } else {
            showNoTicketsAlert()
        }
    }
    
    private func showSkipTicketAlert(skips: Int) {
        let alertView = SkipAlertView(
            availableTickets: skips,
            onUseTicket: { [weak self] in
                // Dismiss the SwiftUI overlay
                self?.dismiss(animated: true) {
                    SkipManager.shared.useSkip()
                    self?.saveCheckpointCompletion()
                    self?.goToNextStoryPage()
                }
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        let hostVC = UIHostingController(rootView: alertView)
        hostVC.view.backgroundColor = .clear
        hostVC.modalPresentationStyle = .overCurrentContext
        hostVC.modalTransitionStyle = .crossDissolve
        present(hostVC, animated: true)
    }
    
    private func showNoTicketsAlert() {
        let alertView = NoTicketsAlertView(
            onDismiss: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        let hostVC = UIHostingController(rootView: alertView)
        hostVC.view.backgroundColor = .clear
        hostVC.modalPresentationStyle = .overCurrentContext
        hostVC.modalTransitionStyle = .crossDissolve
        present(hostVC, animated: true)
    }

}

// MARK: - Video Playback
private extension CheckpointViewController {
    func playVideoInView() {
        guard let path = Bundle.main.path(forResource: "checkpointTeddy", ofType: "mp4") else { return }
        player = AVPlayer(url: URL(fileURLWithPath: path))
        playerLayer = AVPlayerLayer(player: player)
        player?.isMuted = true
        playerLayer?.frame        = videoContainerView.bounds
        playerLayer?.videoGravity = .resizeAspectFill
        if let playerLayer { videoContainerView.layer.addSublayer(playerLayer) }
        player?.play()

        NotificationCenter.default.addObserver(
            self, selector: #selector(loopVideo),
            name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem
        )
    }

    func stopAndResetVideo() { player?.pause(); player?.seek(to: .zero) }
    func playVideoAgain()    { player?.seek(to: .zero); player?.play() }
    @objc func loopVideo()   { player?.seek(to: .zero); player?.play() }
}

// MARK: - UI Setup & State
private extension CheckpointViewController {
    func setupUI() {
        titleView.layer.cornerRadius = 50
        titleView.layer.borderColor  = UIColor.systemYellow.cgColor
        titleView.layer.borderWidth  = 3.0

        backView.layer.cornerRadius = 25
        backView.layer.borderColor  = UIColor.systemYellow.cgColor
        backView.layer.borderWidth  = 3.0

        textView.layer.cornerRadius = 25
        textView.layer.borderColor  = UIColor.systemYellow.cgColor
        textView.layer.borderWidth  = 1.0

        dialogueView.layer.cornerRadius  = 12
        dialogueView.layer.shadowColor   = UIColor.systemYellow.cgColor
        dialogueView.layer.shadowOpacity = 0.3
        dialogueView.layer.shadowOffset  = CGSize(width: 0, height: 5)
        dialogueView.layer.shadowRadius  = 10
        dialogueView.layer.masksToBounds = false

        checkpointLabel.text = currentEvaluationText
        checkpointLabel.font         = fontForStory()
        checkpointLabel.numberOfLines = 0

        micButton.setImage(UIImage(systemName: "microphone.fill"), for: .normal)

        previousScoresButton?.layer.cornerRadius = (previousScoresButton?.frame.height ?? 0) / 2
        previousScoresButton?.clipsToBounds = true
        configureSkipButtonStyle()
        
        // Initial Skip Button State: Disabled until first failure
        skipButton?.isEnabled = false
        skipButton?.alpha = 0.5
    }

    func configureSkipButtonStyle() {
        let font = UIFont(name: "ArialRoundedMTBold", size: 21) ?? UIFont.systemFont(ofSize: 21)

        skipButton?.configuration = nil
        skipButton?.backgroundColor = UIColor(red: 0.4782714844, green: 0.3479003906, blue: 0.2358398587, alpha: 1)
        skipButton?.setTitle(nil, for: .normal)
        skipButton?.setTitle(nil, for: .disabled)
        skipButton?.setAttributedTitle(
            NSAttributedString(
                string: "Skip",
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.white
                ]
            ),
            for: .normal
        )
        skipButton?.setAttributedTitle(
            NSAttributedString(
                string: "Skip",
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.white.withAlphaComponent(0.65)
                ]
            ),
            for: .disabled
        )
        skipButton?.layer.cornerRadius = 30
        skipButton?.clipsToBounds = true
    }

    func updateInstructionText() {
        let remaining = maxAttempts - attemptCount
        if attemptCount == 0 {
            instructionLabel.text = "Read this out for me.\nYou have 3 tries!"
        } else if remaining == 1 {
            instructionLabel.text = "1 try left.\n You've got this!"
        } else {
            instructionLabel.text = "\(remaining) tries left.\n Let's try again!"
        }
        instructionLabel.textAlignment = .center
    }

    func showCompletedState() {
        hasPerfectScore = true
        micButton.setImage(UIImage(systemName: "arrow.right.circle.fill"), for: .normal)
        micButton.tintColor = .systemGreen

        let allWordsInText = checkpointItem.text.gradableWords
        let attributed = checkpointItem.text.colored(
            matching: allWordsInText,
            font: checkpointLabel.font ?? UIFont.systemFont(ofSize: 30)
        )
        checkpointLabel.attributedText = attributed
    }

    func showActiveState() {
        hasPerfectScore  = false
        attemptCount     = 0
        currentEvaluationText = originalCheckpointText // Reset to original paragraph
        adaptiveRetryTexts.removeAll()
        
        micButton.setImage(UIImage(systemName: "microphone.fill"), for: .normal)
        micButton.tintColor = .systemBlue
        checkpointLabel.textColor      = .label
        checkpointLabel.attributedText = nil
        checkpointLabel.text = currentEvaluationText
    }
    
    /// Check if user has ever attempted this checkpoint (current session OR past sessions)
    func hasAttemptedBefore() -> Bool {
        // Current session attempt
        if attemptCount > 0 { return true }
        // Past session attempts (stored in CoreData)
        let title = story?.title ?? ""
        let number = fallbackPageIndex + 1
        let history = checkpointHistoryManager.getAttempts(for: title, checkpointNumber: number)
        return !history.isEmpty
    }
    
    func updateSkipButtonState() {
        if hasAttemptedBefore() {
            skipButton?.isEnabled = true
            skipButton?.alpha = 1.0
        } else {
            skipButton?.isEnabled = false
            skipButton?.alpha = 0.5
        }
    }
}

// MARK: - Speech Recognition
private extension CheckpointViewController {
    func startListening() {
        micButton.isEnabled = true
        checkpointLabel.attributedText = nil
        checkpointLabel.text = currentEvaluationText
        checkpointLabel.textColor      = .label

        hasPerfectScore    = false
        currentTranscript  = ""
        hardResetAudio()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio,
                                         options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("CheckpointVC: audio session error – \(error)")
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 13, *) { recognitionRequest.requiresOnDeviceRecognition = false }

        let inputNode = audioEngine.inputNode

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                self.currentTranscript = result.bestTranscription.formattedString
                if result.isFinal {
                    self.stopTimer?.invalidate()
                    self.stopTimer = nil
                    self.hardResetAudio()
                    self.evaluateSpokenText(self.currentTranscript)
                }
            }
            if error != nil {
                self.hardResetAudio()
                self.micButton.setImage(UIImage(systemName: "microphone.fill"), for: .normal)
                self.micButton.isEnabled = true
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()
        micButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
    }

    func startGracefulStop() {
        micButton.isEnabled = false
        recognitionRequest?.endAudio()
        stopTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.hardResetAudio()
            self.evaluateSpokenText(self.currentTranscript)
        }
    }

    func hardResetAudio() {
        stopTimer?.invalidate()
        stopTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

// MARK: - Evaluation & Scoring
private extension CheckpointViewController {

    func evaluateSpokenText(_ spokenText: String) {
        stopTimer?.invalidate()
        stopTimer = nil

        let normalizedSpoken = spokenText.allWords.joined(separator: " ")
        let cleanText = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else {
            micButton.setImage(UIImage(systemName: "microphone.fill"), for: .normal)
            micButton.isEnabled = true
            return
        }

        let referenceText = currentEvaluationText

        let targetWords = referenceText.gradableWords
        let spokenWords = normalizedSpoken.allWords

            // Only include words that were actually in the original text but not in the spoken text
            let incorrectWords = targetWords.filter { target in
                !spokenWords.contains { spoken in
                    spoken.isPhoneticMatch(to: target.lowercased())
                }
            }
            guard spokenWords.count >= 1 else { return }

            let attributed = referenceText.colored(matching: spokenWords, font: checkpointLabel?.font ?? UIFont.systemFont(ofSize: 30))
        checkpointLabel?.attributedText = attributed

        var correctCount = 0
        attributed.enumerateAttribute(NSAttributedString.Key.foregroundColor, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let color = value as? UIColor, color == .systemGreen {
                let fragment = (attributed.string as NSString).substring(with: range)
                correctCount += fragment.gradableWords.count
            }
        }

        let total       = max(targetWords.count, 1)
        let rawAccuracy = Double(correctCount) / Double(total)
        let accuracy    = min(rawAccuracy, 1.0)
        let percent     = Int(accuracy * 100)

        saveAttempt(accuracy: percent, spokenWords: spokenWords)

        let passThreshold: Double = 0.80

        if accuracy >= passThreshold {
            hasPerfectScore = true
            attemptCount    = 0
            saveCheckpointCompletion()
            micButton?.setImage(UIImage(systemName: "checkmark"), for: .normal)
            micButton?.tintColor = .systemGreen
            
            // Disable skip if they passed
            skipButton?.isEnabled = false
            skipButton?.alpha = 0.5

            if isLastCheckpoint() { showStoryCompletionAlert() } else { showCheckpointSuccessAlert() }
        } else {
            attemptCount += 1
            updateInstructionText()
            
            // Enable skip button after first failure
            updateSkipButtonState()

            if attemptCount >= maxAttempts {
                presentCustomAlert(
                    title: "Let's practice",
                    message: "Let's practice some more and try again!",
                    buttonText: "Continue",
                    image: UIImage(named: "mascot_encouraging")
                ) { [weak self] in
                    self?.goToFallbackPage()
                }
                return
            }

            // Adaptation Logic: Generate new sentence for 2nd and 3rd tries
            Task {
                do {
                    print("DEBUG: Incorrect words detected: \(incorrectWords)")
                    // Feed incorrect words from the PREVIOUS try to generate NEW text
                    let newSentence = try await AdaptiveSentenceGenerator.shared.generateSentence(from: incorrectWords)
                    print("DEBUG: AI generated sentence: \(newSentence)")

                    await MainActor.run {
                        if self.presentedViewController != nil {
                            self.dismiss(animated: true) {
                                self.showAdaptiveAlert(newSentence: newSentence)
                            }
                        } else {
                            self.showAdaptiveAlert(newSentence: newSentence)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.presentCustomAlert(
                            title: "Try Again",
                            message: "Let's try once more!",
                            buttonText: "Retry",
                            image: UIImage(named: "mascot_encouraging")
                        ) { [weak self] in
                            self?.micButton.isEnabled = true
                        }
                    }
                }
            }
        }
    }
}
// MARK: - Checkpoint Persistence
private extension CheckpointViewController {

    func isCheckpointCompleted() -> Bool {
        return storyManager.isCheckpointCompleted(storyId: story.id, checkpointText: checkpointItem.text)
    }

    func saveCheckpointCompletion() {
        storyManager.markCheckpointCompleted(storyId: story.id, checkpointText: checkpointItem.text)
        let pageIndex = isLastCheckpoint() ? story.content.count - 1 : nextPageIndex
        storyManager.saveProgress(storyId: story.id, pageIndex: pageIndex, didComplete: isLastCheckpoint() ? true : nil)
    }

    func saveAttempt(accuracy: Int, spokenWords: [String]) {
        var additionalTime: TimeInterval = 0
        if let startTime = checkpointStartTime {
            additionalTime = Date().timeIntervalSince(startTime)
            checkpointStartTime = nil
        }

        let attempt = CheckpointAttempt(
            storyTitle: story?.title ?? "Unknown Story",
            checkpointNumber: (fallbackPageIndex + 1),
            accuracy: accuracy,
            spokenWords: spokenWords,
            timestamp: Date()
        )

        // Attempt Firebase/Firestore save
        checkpointHistoryManager.completeCheckpoint(
            attempt: attempt,
            accuracy: Double(accuracy) / 100.0,
            storyId: story?.id ?? "",
            childId: childManager.currentChild.id?.uuidString ?? "default",
            checkpointText: checkpointItem?.text ?? "",
            readingSessionId: readingSession?.id,
            readingSessionEndTime: Date(),
            additionalTime: additionalTime,
            storyManager: storyManager
        )
        
        // Backup: Local Save (in case Firebase has permission issues)
        let localKey = "local_checkpoint_progress_\(story.id)"
        UserDefaults.standard.set(true, forKey: localKey)

        updatePreviousScoresButtonState()
    }

    func updatePreviousScoresButtonState() {
        let title  = story?.title ?? ""
        let number = fallbackPageIndex + 1
        let history = checkpointHistoryManager.getAttempts(for: title, checkpointNumber: number)
        let hasPreviousScores = !history.isEmpty
        previousScoresButton.isEnabled = hasPreviousScores
        previousScoresButton.alpha     = hasPreviousScores ? 1.0 : 0.4
    }
}



// MARK: - Navigation
private extension CheckpointViewController {
    func goToNextStoryPage() {
        let pages = story.content
        guard nextPageIndex >= 0, nextPageIndex < pages.count else { showStoryCompletionAlert(); return }
        let nextPage = pages[nextPageIndex]
        guard let storyboard else { return }
        let nextVC: UIViewController

        if let imgName = nextPage.imageURL, !imgName.isEmpty {
            guard let vc = storyboard.instantiateViewController(withIdentifier: "ImageLabelReadingVC") as? ImageLabelReadingViewController else { return }
            vc.story = story; vc.currentIndex = nextPageIndex; vc.storyTextString = nextPage.text
            vc.imageName = imgName; vc.readingSession = self.readingSession
            vc.storyManager = self.storyManager
            vc.childManager = self.childManager; vc.checkpointHistoryManager = self.checkpointHistoryManager
            nextVC = vc
        } else {
            guard let vc = storyboard.instantiateViewController(withIdentifier: "LabelReadingVC") as? LabelReadingViewController else { return }
            vc.story = story; vc.currentIndex = nextPageIndex; vc.storyTextString = nextPage.text
            vc.readingSession = self.readingSession
            vc.storyManager = self.storyManager
            vc.childManager = self.childManager; vc.checkpointHistoryManager = self.checkpointHistoryManager
            nextVC = vc
        }

        if let nav = navigationController {
            nav.popViewController(animated: false)
            nav.pushViewController(nextVC, animated: true)
        }
    }

    func goToFallbackPage() {
        let pages = story.content
        let index = max(0, min(fallbackPageIndex, pages.count - 1))
        let page  = pages[index]
        guard let storyboard else { return }
        let nextVC: UIViewController

        if let imgName = page.imageURL, !imgName.isEmpty {
            guard let vc = storyboard.instantiateViewController(withIdentifier: "ImageLabelReadingVC") as? ImageLabelReadingViewController else { return }
            vc.story = story; vc.currentIndex = index; vc.storyTextString = page.text
            vc.imageName = imgName; vc.readingSession = self.readingSession
            vc.storyManager = self.storyManager
            vc.childManager = self.childManager; vc.checkpointHistoryManager = self.checkpointHistoryManager
            nextVC = vc
        } else {
            guard let vc = storyboard.instantiateViewController(withIdentifier: "LabelReadingVC") as? LabelReadingViewController else { return }
            vc.story = story; vc.currentIndex = index; vc.storyTextString = page.text
            vc.readingSession = self.readingSession
            vc.storyManager = self.storyManager
            vc.childManager = self.childManager; vc.checkpointHistoryManager = self.checkpointHistoryManager
            nextVC = vc
        }

        if let nav = navigationController {
            nav.popViewController(animated: false)
            nav.pushViewController(nextVC, animated: true)
        }
    }

    func goToLibrary() {
        endReadingSessionIfNeeded()
        guard let nav = navigationController else { return }
        for vc in nav.viewControllers {
            if vc is ReadingPreviewViewController { nav.popToViewController(vc, animated: true); return }
        }
        nav.popToRootViewController(animated: true)
    }

    func endReadingSessionIfNeeded() {
        guard let session = readingSession, session.endTime == nil else { return }
        storyManager.endReadingSession(session)
        readingSession?.endTime = Date()
    }

    func isLastCheckpoint() -> Bool {
        let pages = story.content
        return !(nextPageIndex >= 0 && nextPageIndex < pages.count)
    }
}

// MARK: - Alerts
private extension CheckpointViewController {
    func presentCustomAlert(title: String, message: String, buttonText: String,
                            image: UIImage?, completion: @escaping () -> Void) {
        guard let alertVC = storyboard?.instantiateViewController(withIdentifier: "CustomAlertVC") as? CustomAlertViewController else { return }
        alertVC.alertTitle   = title
        alertVC.alertMessage = message
        alertVC.buttonText   = buttonText
        alertVC.alertImage   = image
        alertVC.onDismiss    = completion
        alertVC.modalPresentationStyle = .overCurrentContext
        alertVC.modalTransitionStyle   = .crossDissolve
        present(alertVC, animated: true)
    }

    func showCheckpointSuccessAlert() {
        presentCustomAlert(title: "Well done!", message: "You read that perfectly!",
                           buttonText: "Continue", image: UIImage(named: "success_mascot")) { [weak self] in
            self?.goToNextStoryPage()
        }
    }

    func showStoryCompletionAlert() {
        presentCustomAlert(title: "Hooray! ", message: "You finished the story!",
                           buttonText: "Go to Library", image: UIImage(named: "mascot_celebrating")) { [weak self] in
            if let currentStory = self?.story {
                self?.storyManager.saveProgress(
                    storyId: currentStory.id,
                    pageIndex: (currentStory.content.count - 1),
                    didComplete: true)
            }
            self?.goToLibrary()
        }
    }
}

// MARK: - Typography
private extension CheckpointViewController {
    func fontForStory() -> UIFont {
        guard let difficulty = story?.difficulty.lowercased() else {
            return UIFont.systemFont(ofSize: 30)
        }
        switch difficulty {
        case "level 1": return UIFont(name: "ArialMT",           size: 32) ?? UIFont.systemFont(ofSize: 32)
        case "level 2": return UIFont(name: "TrebuchetMS",       size: 30) ?? UIFont.systemFont(ofSize: 30)
        case "level 3": return UIFont(name: "TimesNewRomanPSMT", size: 30) ?? UIFont.systemFont(ofSize: 30)
        default:        return UIFont.systemFont(ofSize: 30)
        }
    }

    func showAdaptiveAlert(newSentence: String) {
        self.currentEvaluationText = newSentence
        self.checkpointLabel.text = newSentence
        self.micButton.setImage(UIImage(systemName: "microphone.fill"), for: .normal)
        self.micButton.isEnabled = true

        self.presentCustomAlert(
            title: "Try this one!",
            message: "I made a special sentence for you with words you missed. Give it a try!",
            buttonText: "Try Again",
            image: UIImage(named: "mascot_encouraging")
        ) { 
            // Wait for mic tap
        }
    }
}
