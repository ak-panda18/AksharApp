import UIKit

class FluencyDrillsViewController: UIViewController,
                                   ExerciseDependencyReceivable, ExerciseReceivesCover,
                                   ExerciseSTTReceivable, ExerciseResumable {

    var phonicsGameplayManager: PhonicsGameplayManager!
    var bundleDataLoader: BundleDataLoader!

    var speechRecognitionManager: SpeechRecognitionManager!
    var gameTimerManager: GameTimerManager!

    var exerciseType: ExerciseType?
    var startingIndex: Int? = nil
    var coverWasShown: Bool = false

    // MARK: - Outlets
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var scoreLabel: UILabel!
    @IBOutlet weak var timerLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var micButton: UIButton!
    @IBOutlet weak var yellowView: UIView!
    @IBOutlet weak var wordLabel: UILabel!
    @IBOutlet weak var nextButton: UIButton!

    // MARK: - Internal Data
    private var items: [FluencyItem] = []
    private var localCurrentIndex = 0
    private var localCorrectCount = 0
    private var roundEnded = false

    // MARK: - Speech Recognition state
    private var isRecording = false
    private var didScoreCurrentWord = false

    // Mic hint label shown to the right of the mic button
    private let micHintLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "Tap and start speaking!"
        lbl.font = UIFont(name: "ArialRoundedMTBold", size: 17) ?? UIFont.boldSystemFont(ofSize: 17)
        lbl.textColor = UIColor(red: 0.478, green: 0.349, blue: 0.235, alpha: 1)
        lbl.textAlignment = .left
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    // MARK: - Lifecycle
    private func verifyDependencies() {
        assert(phonicsGameplayManager != nil, "phonicsGameplayManager was not injected into \(type(of: self))")
        assert(bundleDataLoader != nil, "bundleDataLoader was not injected into \(type(of: self))")
        assert(speechRecognitionManager != nil, "speechRecognitionManager was not injected into \(type(of: self))")
        assert(gameTimerManager != nil, "gameTimerManager was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        styleUI()
        configureGameData()
        styleSubmitButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        micButton.layer.cornerRadius  = micButton.bounds.height / 2
        nextButton.layer.cornerRadius = nextButton.bounds.height / 2
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        gameTimerManager.stop()
        speechRecognitionManager.stopListening()
    }

    // MARK: - Configuration
    private func configureGameData() {
        items = bundleDataLoader.load("FluencyDrillsQuestions", as: [FluencyItem].self)

        if items.isEmpty {
            items = [
                FluencyItem(speakableText: "Cat"),
                FluencyItem(speakableText: "Dog"),
                FluencyItem(speakableText: "Hat")
            ]
        }

        items.shuffle()
        localCurrentIndex = 0
        phonicsGameplayManager.startSession(for: .fluency, totalQuestions: items.count, startPointer: 0)
        loadWord()
    }

    // MARK: - UI Styling
    func styleUI() {
        yellowView.layer.cornerRadius = 16
        yellowView.layer.masksToBounds = true

        progressView.progress         = 1
        progressView.trackTintColor   = .lightGray
        progressView.progressTintColor = .systemGreen

        timerLabel.text     = "30 seconds remaining"
        scoreLabel.isHidden = true
        nextButton.isHidden = true

        // Add hint label to the right of the mic button
        if micHintLabel.superview == nil {
            view.addSubview(micHintLabel)
            NSLayoutConstraint.activate([
                micHintLabel.leadingAnchor.constraint(equalTo: micButton.trailingAnchor, constant: 14),
                micHintLabel.centerYAnchor.constraint(equalTo: micButton.centerYAnchor)
            ])
        }
    }

    func styleSubmitButton() {
        nextButton.configuration    = nil
        nextButton.backgroundColor  = UIColor(red: 117/255, green: 80/255, blue: 50/255, alpha: 1.0)
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.titleLabel?.font = UIFont(name: "ArialRoundedMTBold", size: 35)
        nextButton.layer.cornerRadius = nextButton.bounds.height / 2
        nextButton.clipsToBounds    = true
    }

    // MARK: - Word Flow
    func loadWord() {
        if localCurrentIndex >= items.count {
            localCurrentIndex = 0
            items.shuffle()
        }
        didScoreCurrentWord = false
        scoreLabel.isHidden = true
        wordLabel.text      = items[localCurrentIndex].speakableText
    }

    // MARK: - Timer
    func resetTimer() {
        gameTimerManager.reset()
        timerLabel.text               = "30 seconds remaining"
        progressView.progress         = 1
        progressView.progressTintColor = .systemBlue
    }

    func startTimer() {
        gameTimerManager.onTick = { [weak self] seconds in
            guard let self else { return }
            DispatchQueue.main.async {
                self.timerLabel.text    = "\(seconds) seconds remaining"
                self.progressView.progress = Float(seconds) / 30.0
                if seconds > 20 {
                    self.progressView.progressTintColor = .systemGreen
                } else if seconds > 10 {
                    self.progressView.progressTintColor = .systemOrange
                } else {
                    self.progressView.progressTintColor = .systemRed
                }
            }
        }
        gameTimerManager.onFinished = { [weak self] in
            DispatchQueue.main.async {
                self?.stopListening()
                self?.timerLabel.text           = "Time over!"
                self?.progressView.progress     = 0
                self?.endRound()
            }
        }
        gameTimerManager.start()
    }

    func updateMicIcon() {
        // Always keep the mic icon — the pulse signals listening state
        micButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
    }

    // MARK: - Pulse Animation
    private func startPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue   = 1.05
        pulse.duration  = 0.85
        pulse.autoreverses  = true
        pulse.repeatCount   = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        micButton.layer.add(pulse, forKey: "pulseAnimation")
    }

    private func stopPulseAnimation() {
        micButton.layer.removeAnimation(forKey: "pulseAnimation")
    }

    // MARK: - Actions
    @IBAction func micButtonTapped(_ sender: UIButton) {
        if isRecording {
            stopListening()
        } else {
            resetTimer()
            didScoreCurrentWord = false
            startListening()
            startTimer()
        }
    }

    @IBAction func nextButtonTapped(_ sender: Any) {
        roundEnded        = false
        micButton.isEnabled = true
        localCorrectCount = 0
        localCurrentIndex = 0
        items.shuffle()
        resetTimer()
        loadWord()
        nextButton.isHidden = true
    }

    func startListening() {
        speechRecognitionManager.onWordDetected = { [weak self] spoken in
            guard let self,
                  !self.roundEnded,
                  self.items.indices.contains(self.localCurrentIndex),
                  !self.didScoreCurrentWord,
                  !spoken.isEmpty else { return }

            let expected = self.items[self.localCurrentIndex].speakableText.lowercased()

            if spoken.isPhoneticMatch(to: expected) {
                self.didScoreCurrentWord = true
                self.localCorrectCount  += 1
                self.localCurrentIndex  += 1

                self.phonicsGameplayManager.recordAttempt()
                self.phonicsGameplayManager.recordSuccess()

                DispatchQueue.main.async {
                    self.loadWord()
                    self.didScoreCurrentWord = false
                    self.restartRecognition()
                }
            }
        }
        speechRecognitionManager.startListening()
        isRecording = true
        updateMicIcon()
        // Hide hint label, start pulse, and lock the button while listening
        micHintLabel.isHidden = true
        micButton.isEnabled = false
        startPulseAnimation()
    }

    func restartRecognition() {
        speechRecognitionManager.stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.speechRecognitionManager.startListening()
        }
    }

    func stopListening() {
        speechRecognitionManager.stopListening()
        isRecording = false
        updateMicIcon()
        // Restore hint label, stop pulse, and unlock the button
        stopPulseAnimation()
        micHintLabel.isHidden = false
        micButton.isEnabled = true
    }

    // MARK: - Round End
    func endRound() {
        roundEnded          = true
        micButton.isEnabled = false
        gameTimerManager.stop()
        speechRecognitionManager.stopListening()

        scoreLabel.text      = "You pronounced \(localCorrectCount) words correctly!"
        scoreLabel.textColor = .systemGreen
        scoreLabel.isHidden  = false

        nextButton.setTitle("Next", for: .normal)
        nextButton.isHidden = false
    }

    // MARK: - Navigation
    @IBAction func backButtonTapped(_ sender: Any) {
        phonicsGameplayManager.endSession()
        goBackToPhonicsCover()
    }

    @IBAction func homeButtonTapped(_ sender: Any) {
        phonicsGameplayManager.endSession()
        phonicsGameplayManager.clearCycleProgress()
        goHomeFromPhonics()
    }
}
