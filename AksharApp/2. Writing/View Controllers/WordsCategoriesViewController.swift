import UIKit

class WordsCategoriesViewController: UIViewController {

    // MARK: - Outlets
    @IBOutlet weak var ImageView: UIImageView!
    @IBOutlet weak var titleView: UIView!
    @IBOutlet weak var backView: UIView!
    @IBOutlet weak var dialogueView: UIView!
    @IBOutlet weak var powerWords: UIImageView!
    @IBOutlet weak var letter6: UIImageView!
    @IBOutlet weak var letter5: UIImageView!
    @IBOutlet weak var letter4: UIImageView!
    @IBOutlet weak var letter3: UIImageView!

    // MARK: - Injected
    var writingGameplayManager: WritingGameplayManager!

    // MARK: - Phonics / Exercise Dependencies
        var isExercisesMode: Bool = false
        var phonicsGameplayManager: PhonicsGameplayManager?
        var bundleDataLoader: BundleDataLoader?
        var speechManager: SpeechManager?
        var speechRecognitionManager: SpeechRecognitionManager?
        var gameTimerManager: GameTimerManager?
    
    // MARK: - Lifecycle
    private func verifyDependencies() {
        assert(writingGameplayManager != nil, "writingGameplayManager was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        setupUI()
        setupGestures()
    }

    // MARK: - Setup
    func setupUI() {
        titleView.layer.cornerRadius = 50
        titleView.layer.borderColor  = UIColor.systemYellow.cgColor
        titleView.layer.borderWidth  = 3.0

        backView.layer.cornerRadius = 25
        backView.layer.borderColor  = UIColor.systemYellow.cgColor
        backView.layer.borderWidth  = 3.0

        dialogueView.layer.cornerRadius  = 12
        dialogueView.layer.shadowColor   = UIColor.systemYellow.cgColor
        dialogueView.layer.shadowOpacity = 0.3
        dialogueView.layer.shadowOffset  = CGSize(width: 0, height: 5)
        dialogueView.layer.shadowRadius  = 10
        dialogueView.layer.masksToBounds = false

        [letter3, letter4, letter5, letter6, powerWords].forEach { $0?.layer.cornerRadius = 20 }
        
        if let img = customImage3 { letter3.image = img }
        if let img = customImage4 { letter4.image = img }
        if let img = customImage5 { letter5.image = img }
        if let img = customImage6 { letter6.image = img }
        if let img = customPowerImage { powerWords.image = img }
        // 👇 NEW: Update title if in Exercises mode
        if isExercisesMode {
            
            // Clear out the original "Word Categories" label/image from the container
            titleView.subviews.forEach { $0.removeFromSuperview() }
            
            let titleLabel = UILabel()
            titleLabel.text = "Exercises"
            // Bumped font size from 34 to 44
            titleLabel.font = UIFont(name: "Arial Rounded MT Bold", size: 44) ?? UIFont.boldSystemFont(ofSize: 44)
            titleLabel.textColor = .brown
            titleLabel.textAlignment = .center
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleView.addSubview(titleLabel)
            
            NSLayoutConstraint.activate([
                titleLabel.centerXAnchor.constraint(equalTo: titleView.centerXAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: titleView.centerYAnchor)
            ])
        }
    }

    private func setupGestures() {
        func addTap(to view: UIView, action: Selector) {
            let tap = UITapGestureRecognizer(target: self, action: action)
            view.addGestureRecognizer(tap)
            view.isUserInteractionEnabled = true
        }
        addTap(to: letter3,    action: #selector(didTap3))
        addTap(to: letter4,    action: #selector(didTap4))
        addTap(to: letter5,    action: #selector(didTap5))
        addTap(to: letter6,    action: #selector(didTap6))
        addTap(to: powerWords, action: #selector(didTapPower))
    }

    // MARK: - Actions
    @objc func didTap3()     { openCategory(.threeLetter) }
    @objc func didTap4()     { openCategory(.fourLetter) }
    @objc func didTap5()     { openCategory(.fiveLetter) }
    @objc func didTap6()     { openCategory(.sixLetter) }
    @objc func didTapPower() { openCategory(.power) }

    @IBAction func backButtonTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Navigation Logic
    private func openCategory(_ category: TracingCategory) {
            // 👇 NEW: Intercept for Exercises mode
            if isExercisesMode {
                openPhonicsCover(for: category)
                return
            }

            writingGameplayManager.lastActiveCategory = category.rawValue

            let index      = writingGameplayManager.getHighestUnlockedIndex(category: category.rawValue)
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let vc: UIViewController

        if writingGameplayManager.loadTwoDrawings(index: index, category: category.rawValue) != nil {
            guard let c = storyboard.instantiateViewController(withIdentifier: "SixWordTraceVC") as? SixWordTraceViewController else { return }
            c.currentWordIndex       = index
            c.selectedCategory       = category
            c.writingGameplayManager = writingGameplayManager
            vc = c
        } else if writingGameplayManager.loadOneDrawing(index: index, category: category.rawValue) != nil {
            guard let c = storyboard.instantiateViewController(withIdentifier: "TwoWordTraceVC") as? TwoWordTraceViewController else { return }
            c.currentWordIndex       = index
            c.selectedCategory       = category
            c.writingGameplayManager = writingGameplayManager
            vc = c
        } else {
            guard let c = storyboard.instantiateViewController(withIdentifier: "OneWordTraceVC") as? OneWordTraceViewController else { return }
            c.currentWordIndex       = index
            c.selectedCategory       = category
            c.writingGameplayManager = writingGameplayManager
            vc = c
        }

        navigationController?.pushViewController(vc, animated: true)
    }
    // MARK: - Phonics Routing
        private func openPhonicsCover(for category: TracingCategory) {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            guard let coverVC = storyboard.instantiateViewController(withIdentifier: "PhonicsCoverVC") as? PhonicsCoverViewController else { return }
            
            let targetTitle: String
            switch category {
            case .threeLetter: targetTitle = "Sound Detective"
            case .fourLetter:  targetTitle = "Word Builder"
            case .fiveLetter:  targetTitle = "Quiz My Story"
            case .sixLetter:   targetTitle = "Rhymewords"
            case .power:       targetTitle = "Fluency Drills"
            default:           targetTitle = "Sound Detective"
            }
            
            // Find the matching ExerciseType
            if let exercise = ExerciseType.allCases.first(where: { $0.titleText.lowercased().contains(targetTitle.lowercased()) }) {
                coverVC.chosenExercise = exercise
            } else {
                coverVC.chosenExercise = ExerciseType.allCases.first
            }
            
            // Inject dependencies
            coverVC.phonicsGameplayManager = phonicsGameplayManager
            coverVC.bundleDataLoader = bundleDataLoader
            coverVC.speechManager = speechManager
            coverVC.speechRecognitionManager = speechRecognitionManager
            coverVC.gameTimerManager = gameTimerManager
            
            navigationController?.pushViewController(coverVC, animated: true)
        }
    
// MARK: - Changes made on 26/03/2026
  
    var customImage3: UIImage?
    var customImage4: UIImage?
    var customImage5: UIImage?
    var customImage6: UIImage?
    var customPowerImage: UIImage?
}
