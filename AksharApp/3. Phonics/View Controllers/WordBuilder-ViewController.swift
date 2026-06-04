import UIKit

class WordBuilder_ViewController: UIViewController,
                                 ExerciseDependencyReceivable, ExerciseReceivesCover,
                                 ExerciseResumable {

    var phonicsGameplayManager: PhonicsGameplayManager!
    var bundleDataLoader: BundleDataLoader!

    var exerciseType:  ExerciseType?
    var startingIndex: Int?
    var coverWasShown: Bool = false

    var currentIndex: Int { phonicsGameplayManager.getCurrentIndex() }

    // MARK: - Outlets
    @IBOutlet weak var feedbackLabel: UILabel!
    @IBOutlet weak var wordImage: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var submitButton: UIButton!

    @IBOutlet weak var optionButton1: UIButton!
    @IBOutlet weak var optionButton2: UIButton!
    @IBOutlet weak var optionButton3: UIButton!
    @IBOutlet weak var answerView1: UIView!
    @IBOutlet weak var answerView2: UIView!
    @IBOutlet weak var answerView3: UIView!

    // MARK: - Internal State
    private var questions: [WordBuilderQuestion] = []
    private var question: WordBuilderQuestion?

    private var filledTiles:   [Int?]   = []
    private var shuffledTiles: [String] = []
    private var isAnswerLocked = false

    private var answerViews:   [UIView]   { [answerView1,   answerView2,   answerView3] }
    private var optionButtons: [UIButton] { [optionButton1, optionButton2, optionButton3] }

    // MARK: - Lifecycle
    private func verifyDependencies() {
        assert(phonicsGameplayManager != nil, "phonicsGameplayManager was not injected into \(type(of: self))")
        assert(bundleDataLoader != nil, "bundleDataLoader was not injected into \(type(of: self))")
    }

    override func viewDidLoad() { 
        super.viewDidLoad()
        verifyDependencies()
        configureGameData()
        setupTapGestures()
        loadCurrentQuestion()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyInitialStyles()
    }

    // MARK: - Configuration
    private func configureGameData() {
        questions = bundleDataLoader.load("WordBuilderQuestions", as: [WordBuilderQuestion].self)
        phonicsGameplayManager.startSession(
            for: .wordBuilder,
            totalQuestions: questions.count,
            startPointer: startingIndex ?? 0
        )
    }

    // MARK: - Styling
    private func applyInitialStyles() {
        answerViews.forEach { view in
            view.layer.cornerRadius = view.bounds.height / 2
            view.layer.borderWidth  = 2
            view.layer.borderColor  = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 0.25).cgColor
            view.clipsToBounds      = true
        }
        styleSubmitButton()
    }

    private func styleOptionButton(_ button: UIButton) {
        button.configuration = nil
        button.backgroundColor  = UIColor(red: 1.0, green: 0.976, blue: 0.839, alpha: 1)
        button.setTitleColor(.brown, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 28, weight: .semibold)
        button.layer.cornerRadius = button.bounds.height / 2
        button.layer.borderWidth  = 2
        button.layer.borderColor  = UIColor(red: 0.91, green: 0.78, blue: 0.44, alpha: 1).cgColor
    }

    private func styleSubmitButton() {
        submitButton.configuration = nil
        submitButton.backgroundColor   = UIColor(red: 117/255, green: 80/255, blue: 50/255, alpha: 1.0)
        submitButton.setTitleColor(.white, for: .normal)
        submitButton.layer.cornerRadius = submitButton.bounds.height / 2
        submitButton.titleLabel?.font   = UIFont(name: "Arial Rounded MT Bold", size: 35)
    }

    // MARK: - Question Flow
    func loadCurrentQuestion() {
        let index = phonicsGameplayManager.getCurrentIndex()
        guard questions.indices.contains(index) else { return }

        let q       = questions[index]
        question    = q
        isAnswerLocked = false

        submitButton.setTitle("Submit", for: .normal)
        feedbackLabel.isHidden = true
        wordImage.image        = UIImage(named: q.imageName)
        shuffledTiles          = Self.shuffledDifferentFromOriginal(q.tiles)
        filledTiles            = Array(repeating: nil, count: q.blanksCount)

        for (i, button) in optionButtons.enumerated() {
            button.setTitle(shuffledTiles[i], for: .normal)
            button.tag    = i
            button.isHidden = false
            styleOptionButton(button)
        }
        answerViews.forEach { $0.subviews.forEach { $0.removeFromSuperview() } }
    }

    private func moveToNextQuestion() {
        removeSticker()
        phonicsGameplayManager.advanceToNext()
        loadCurrentQuestion()
    }

    // MARK: - Actions
    @IBAction func optionTapped(_ sender: UIButton) {
        guard let emptyIndex = filledTiles.firstIndex(where: { $0 == nil }) else { return }
        addTileText(shuffledTiles[sender.tag], to: answerViews[emptyIndex])
        filledTiles[emptyIndex] = sender.tag
        sender.isHidden = true
    }

    @IBAction func submitTapped(_ sender: UIButton) {
        if isAnswerLocked { moveToNextQuestion(); return }
        guard let q = question else { return }

        phonicsGameplayManager.recordAttempt()

        let assembled = filledTiles.compactMap { $0 }.map { shuffledTiles[$0] }.joined()

        if assembled.lowercased() == q.correct.lowercased() {
            phonicsGameplayManager.recordSuccess()
            feedbackLabel.text  = "Correct!"
            feedbackLabel.textColor = .systemGreen
            submitButton.setTitle("Next", for: .normal)
            isAnswerLocked = true
            showStickerAtTopRight(assetName: "YouDidIt")
        } else {
            feedbackLabel.text      = "Try again!"
            feedbackLabel.textColor = .systemRed
        }
        feedbackLabel.isHidden = false
    }

    // MARK: - Navigation
    @IBAction func homeButtonTappped(_ sender: Any) {
        phonicsGameplayManager.endSession()
        phonicsGameplayManager.clearCycleProgress()
        goHomeFromPhonics()
    }

    @IBAction func backButtonTapped(_ sender: Any) {
        phonicsGameplayManager.endSession()
        phonicsGameplayManager.clearCycleProgress()
        if let coverVC = navigationController?.viewControllers.last(where: { $0 is PhonicsCoverViewController }) as? PhonicsCoverViewController {
            coverVC.resumeCyclePointer = phonicsGameplayManager.getCyclePointer()
        }
        goBackToPhonicsCover()
    }

    // MARK: - Answer Tile UI
    func addTileText(_ text: String, to view: UIView) {
        let label = UILabel(frame: view.bounds)
        label.text          = text
        label.font          = .systemFont(ofSize: 30, weight: .semibold)
        label.textAlignment = .center
        label.backgroundColor = UIColor(red: 1.0, green: 0.97, blue: 0.85, alpha: 1.0)
        label.textColor     = .brown
        label.layer.cornerRadius  = view.bounds.height / 2
        label.layer.masksToBounds = true
        label.layer.borderWidth   = 2
        label.layer.borderColor   = UIColor.brown.cgColor
        label.autoresizingMask    = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
    }

    @objc func answerViewTapped(_ sender: UITapGestureRecognizer) {
        guard !isAnswerLocked, let view = sender.view, let tileIndex = filledTiles[view.tag] else { return }
        optionButtons[tileIndex].isHidden = false
        filledTiles[view.tag] = nil
        view.subviews.forEach { $0.removeFromSuperview() }
    }

    func setupTapGestures() {
        for (i, view) in answerViews.enumerated() {
            view.tag = i
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(answerViewTapped(_:))))
            view.isUserInteractionEnabled = true
        }
    }

    // MARK: - Shuffle Helper
    /// Returns a shuffled copy of `tiles` that is guaranteed to differ from
    /// the original order (i.e. the correct answer sequence), so the child
    /// can never be handed the answer on a plate.
    private static func shuffledDifferentFromOriginal(_ tiles: [String]) -> [String] {
        guard tiles.count > 1 else { return tiles } // nothing to shuffle for a single tile
        var result = tiles
        var attempts = 0
        repeat {
            result = tiles.shuffled()
            attempts += 1
        } while result == tiles && attempts < 20
        return result
    }
}
