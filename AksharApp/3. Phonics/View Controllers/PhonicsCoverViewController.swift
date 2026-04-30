import UIKit

class PhonicsCoverViewController: UIViewController {

    // MARK: - Outlets
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var coverImageView: UIImageView!
    @IBOutlet weak var subtitleLabel: UILabel!

    // MARK: - Properties
    var chosenExercise: ExerciseType!
    var resumeCyclePointer: Int?

    // MARK: - Injected
    var phonicsGameplayManager: PhonicsGameplayManager!
    var bundleDataLoader: BundleDataLoader!
    var speechManager: SpeechManager!
    var speechRecognitionManager: SpeechRecognitionManager!
    var gameTimerManager: GameTimerManager!

    // MARK: - Lifecycle
    private func verifyDependencies() {
        assert(phonicsGameplayManager != nil, "phonicsGameplayManager was not injected into \(type(of: self))")
        assert(bundleDataLoader != nil, "bundleDataLoader was not injected into \(type(of: self))")
        assert(speechManager != nil, "speechManager was not injected into \(type(of: self))")
        assert(speechRecognitionManager != nil, "speechRecognitionManager was not injected into \(type(of: self))")
        assert(gameTimerManager != nil, "gameTimerManager was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        setupUI()
    }

    private func setupUI() {
        chosenExercise = chosenExercise ?? ExerciseType.allCases.first

        coverImageView.image = UIImage(named: chosenExercise.coverImageName)
        titleLabel.text      = chosenExercise.titleText
        subtitleLabel.text   = chosenExercise.subtitleText
    }

    // MARK: - Actions
    @IBAction func startButtonTapped(_ sender: UIButton) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        let vc = sb.instantiateViewController(withIdentifier: chosenExercise.storyboardID)

        if let depReceiver = vc as? ExerciseDependencyReceivable {
            depReceiver.phonicsGameplayManager = phonicsGameplayManager
            depReceiver.bundleDataLoader       = bundleDataLoader
        }

        if let speechReceiver = vc as? ExerciseSpeechReceivable {
            speechReceiver.speechManager = speechManager
        }

        if let sttReceiver = vc as? ExerciseSTTReceivable {
            sttReceiver.speechRecognitionManager = speechRecognitionManager
            sttReceiver.gameTimerManager         = gameTimerManager
        }

        if var receiver = vc as? ExerciseReceivesCover {
            receiver.exerciseType  = chosenExercise
            receiver.coverWasShown = true
        }

        if var resumable = vc as? ExerciseResumable {
            resumable.startingIndex = resumeCyclePointer ?? 0
        }

        navigationController?.pushViewController(vc, animated: false)
    }

    @IBAction func backButtonTapped(_ sender: Any) {
            // Pops the current view controller off the stack,
            // returning to whichever screen pushed it here.
            navigationController?.popViewController(animated: true)
        }

    @IBAction func homeButtonTapped(_ sender: Any) {
        goHomeFromPhonics()
    }
}
