import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "WritingPreviewViewController")

class WritingPreviewViewController: UIViewController {

    // MARK: - Outlets
    @IBOutlet weak var demoView: UIView!
    @IBOutlet weak var letterCardVIew: UIView!
    @IBOutlet weak var numberCardView: UIView!
    @IBOutlet weak var wordCardView: UIView!

    @IBOutlet weak var letterImage: UIImageView!
    @IBOutlet weak var numberImage: UIImageView!
    @IBOutlet weak var wordImage: UIImageView!

    @IBOutlet weak var currentLetterView: UIView!
    @IBOutlet weak var nextNumberView: UIView!
    @IBOutlet weak var nextWordView: UIView!
    @IBOutlet var currentLetterLabel: UILabel!
    @IBOutlet var currentNumberLabel: UILabel!
    @IBOutlet var currentWordLabel: UILabel!

    @IBOutlet weak var letterProgressView: UIProgressView!
    @IBOutlet var numberProgressView: UIProgressView!
    @IBOutlet weak var wordProgressView: UIProgressView!

    // MARK: - Injected
    var writingGameplayManager: WritingGameplayManager!
    
    // Guided Learning Path
    weak var sessionDelegate: AnyObject?
    var orchestrator: SessionOrchestrator?


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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        bindUI()
    }

    // MARK: - UI Binding
    private func bindUI() {
        currentLetterLabel.text = writingGameplayManager.currentLetterDisplay()
        currentNumberLabel.text = writingGameplayManager.currentNumberDisplay()
        currentWordLabel.text   = writingGameplayManager.currentWordDisplay()

        letterProgressView.progress = writingGameplayManager.letterProgress()
        numberProgressView.progress = writingGameplayManager.numberProgress()
        wordProgressView.progress   = writingGameplayManager.wordProgress()
    }

    // MARK: - Setup
    private func setupUI() {
        let cardStrokeColor = UIColor(red: 250/255.0, green: 239/255.0, blue: 184/255.0, alpha: 1.0)
        [letterCardVIew, numberCardView, wordCardView].forEach {
            $0?.layer.borderColor  = cardStrokeColor.cgColor
            $0?.layer.borderWidth  = 7
            $0?.layer.cornerRadius = 25
        }
        [letterImage, numberImage, wordImage].forEach { $0?.layer.cornerRadius = 25 }
        [currentLetterView, nextNumberView, nextWordView].forEach {
            $0?.layer.cornerRadius = ($0?.frame.height ?? 0) / 2
        }
    }

    private func setupGestures() {
        let letterTap = UITapGestureRecognizer(target: self, action: #selector(letterCardTapped))
        letterCardVIew.addGestureRecognizer(letterTap)
        letterCardVIew.isUserInteractionEnabled = true

        let numberTap = UITapGestureRecognizer(target: self, action: #selector(numberCardTapped))
        numberCardView.addGestureRecognizer(numberTap)
        numberCardView.isUserInteractionEnabled = true

        let wordTap = UITapGestureRecognizer(target: self, action: #selector(wordCardTapped))
        wordCardView.addGestureRecognizer(wordTap)
        wordCardView.isUserInteractionEnabled = true
    }

    // MARK: - Actions
    @IBAction func backToHomeTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @objc private func letterCardTapped(_ sender: UITapGestureRecognizer) {
        openLatest(contentType: .letters)
    }

    @objc private func numberCardTapped(_ sender: UITapGestureRecognizer) {
        openLatest(contentType: .numbers)
    }

    @objc private func wordCardTapped(_ sender: UITapGestureRecognizer) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let catVC = sb.instantiateViewController(withIdentifier: "WordsCategoriesViewController")
                as? WordsCategoriesViewController else { return }
        catVC.writingGameplayManager = writingGameplayManager
        navigationController?.pushViewController(catVC, animated: true)
    }

    // MARK: - Deep-link entry point
    func buildDeepLinkStack(startingWith baseStack: [UIViewController]) -> [UIViewController] {
        var stack    = baseStack
        let category = writingGameplayManager.lastActiveCategory
        let sb       = UIStoryboard(name: "Main", bundle: nil)

        if category == "letters" || category == "numbers" {
            let contentType: WritingContentType = (category == "letters") ? .letters : .numbers
            let index = writingGameplayManager.getHighestUnlockedIndex(category: category)

            let identifier: String
            if writingGameplayManager.loadTwoDrawings(index: index, category: category) != nil {
                identifier = "SixLetterTraceVC"
            } else if writingGameplayManager.loadOneDrawing(index: index, category: category) != nil {
                identifier = "TwoLetterTraceVC"
            } else {
                identifier = "OneLetterTraceVC"
            }

            guard let vc = sb.instantiateViewController(withIdentifier: identifier) as? BaseTraceViewController else { return stack }
            vc.contentType            = contentType
            vc.currentIndex           = index
            vc.writingGameplayManager = writingGameplayManager
            vc.orchestrator           = orchestrator
            stack.append(vc)

        } else {
            guard let catVC = sb.instantiateViewController(withIdentifier: "WordsCategoriesViewController")
                    as? WordsCategoriesViewController else { return stack }
            catVC.writingGameplayManager = writingGameplayManager
            stack.append(catVC)

            if let categoryEnum = TracingCategory(rawValue: category) {
                let index = writingGameplayManager.getHighestUnlockedIndex(category: category)
                let identifier: String
                if writingGameplayManager.loadTwoDrawings(index: index, category: category) != nil {
                    identifier = "SixWordTraceVC"
                } else if writingGameplayManager.loadOneDrawing(index: index, category: category) != nil {
                    identifier = "TwoWordTraceVC"
                } else {
                    identifier = "OneWordTraceVC"
                }

                if let wordVC = sb.instantiateViewController(withIdentifier: identifier) as? BaseTraceViewController {
                    wordVC.writingGameplayManager = writingGameplayManager
                    wordVC.orchestrator = orchestrator
                    if let one = wordVC as? OneWordTraceViewController {
                        one.currentWordIndex = index; one.selectedCategory = categoryEnum
                    } else if let two = wordVC as? TwoWordTraceViewController {
                        two.currentWordIndex = index; two.selectedCategory = categoryEnum
                    } else if let six = wordVC as? SixWordTraceViewController {
                        six.currentWordIndex = index; six.selectedCategory = categoryEnum
                    }
                    stack.append(wordVC)
                }
            }
        }
        return stack
    }

    // MARK: - Navigation (Letters / Numbers)
    private func openLatest(contentType: WritingContentType) {
        let categoryKey = (contentType == .letters) ? "letters" : "numbers"
        writingGameplayManager.lastActiveCategory = categoryKey

        let index = writingGameplayManager.getHighestUnlockedIndex(category: categoryKey)
        let sb    = UIStoryboard(name: "Main", bundle: nil)

        let identifier: String
        if writingGameplayManager.loadTwoDrawings(index: index, category: categoryKey) != nil {
            identifier = "SixLetterTraceVC"
        } else if writingGameplayManager.loadOneDrawing(index: index, category: categoryKey) != nil {
            identifier = "TwoLetterTraceVC"
        } else {
            identifier = "OneLetterTraceVC"
        }

        guard let vc = sb.instantiateViewController(withIdentifier: identifier) as? BaseTraceViewController else {
            logger.error("WritingPreviewVC: could not instantiate '\(identifier)' — check Storyboard ID")
            return
        }

        vc.contentType            = contentType
        vc.currentIndex           = index
        vc.writingGameplayManager = writingGameplayManager
        vc.orchestrator           = orchestrator
        navigationController?.pushViewController(vc, animated: true)
    }
}
