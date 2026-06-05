import UIKit
import PencilKit
import AVFoundation

class TwoLetterTraceViewController: BaseTraceViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    // MARK: - Properties
    var currentLetterIndex: Int {
        get { return currentIndex }
        set { currentIndex = newValue }
    }

    private var isFullyCompleted: Bool {
        return paneIsCompleted.allSatisfy { $0 }
    }

    // MARK: - Outlets
    @IBOutlet weak var yellowView: UIView!
    @IBOutlet weak var speakerButton: UIView!
    @IBOutlet weak var alphabetCollectionView: UICollectionView!
    @IBOutlet weak var backChevronButton: UIButton!
    @IBOutlet weak var nextChevronButton: UIButton!
    @IBOutlet weak var traceCompleteButton: UIButton!
    @IBOutlet weak var retryButton: UIButton!
    @IBOutlet weak var playButton: UIButton!

    @IBOutlet weak var topLetterImageView: UIImageView!
    @IBOutlet weak var topCommittedDrawingImageView: UIImageView!
    @IBOutlet weak var topTransientDrawingImageView: UIImageView!

    @IBOutlet weak var bottomLetterImageView: UIImageView!
    @IBOutlet weak var bottomCommittedDrawingImageView: UIImageView!
    @IBOutlet weak var bottomTransientDrawingImageView: UIImageView!

    override var traceStage: String { return "two" }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        brushWidth = 40
        writingGameplayManager.startNewSession()

        initPaneArrays(count: 2)
        paneLetterImageViews = [topLetterImageView, bottomLetterImageView]

        setupShapeLayer(for: topLetterImageView)
        setupShapeLayer(for: bottomLetterImageView)

        let topCanvas    = setupCanvas(in: topCommittedDrawingImageView)
        let bottomCanvas = setupCanvas(in: bottomCommittedDrawingImageView)
        paneCommittedCanvases = [topCanvas, bottomCanvas]

        speakerButton.isUserInteractionEnabled = true

        setupUIAppearance()
        setupCollectionView()
        showLetter(at: currentIndex)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNextChevronState()
        alphabetCollectionView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startTraceAnimationForPane0(force: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTraceAnimation()
    }

    // MARK: - UI Setup
    private func setupCollectionView() {
        alphabetCollectionView.delegate = self
        alphabetCollectionView.dataSource = self
        if let layout = alphabetCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        }
    }

    private func setupUIAppearance() {
        applyBorderStyle(to: speakerButton, borderColor: themeBrown)
        applyBorderStyle(to: retryButton, borderColor: themeBrown)
        applyBorderStyle(to: playButton, borderColor: themeBrown)
        applyBorderStyle(to: traceCompleteButton, borderColor: themeBrown)
        applyBorderStyle(to: alphabetCollectionView, borderColor: themeYellow, borderWidth: 2, cornerRadius: 20)

        alphabetCollectionView.layer.borderWidth = 2
        alphabetCollectionView.layer.cornerRadius = 20

        yellowView.layer.cornerRadius = 25
        retryButton.isHidden = false

        nextChevronButton.isEnabled = false
        nextChevronButton.alpha = 0.4

        topLetterImageView.isUserInteractionEnabled = false
        bottomLetterImageView.isUserInteractionEnabled = false
        topCommittedDrawingImageView.isUserInteractionEnabled = false
        bottomCommittedDrawingImageView.isUserInteractionEnabled = false
    }

    // MARK: - Content Loading
    private func showLetter(at index: Int) {
        currentIndex = index
        let category = categoryKey

        let contentProvider = TraceContentProvider(writingGameplayManager: writingGameplayManager)
        let (paneImages, maskNames) = contentProvider.paneImages(index: index, contentType: contentType)

        topLetterImageView.image    = paneImages[0]
        bottomLetterImageView.image = paneImages[1]

        paneMaskAssetNames = maskNames
        loadMasks(forPane: 0, assetNames: paneMaskAssetNames)
        loadMasks(forPane: 1, assetNames: paneMaskAssetNames)

        if let (top, bottom) = writingGameplayManager.loadTwoDrawings(index: currentIndex, category: category) {
            paneCommittedCanvases[0].drawing = top
            paneCommittedCanvases[1].drawing = bottom

            paneIsCompleted[0]       = !top.strokes.isEmpty
            paneCurrentMaskIndex[0]  = top.strokes.isEmpty ? 0 : 999
            paneIsCompleted[1]       = !bottom.strokes.isEmpty
            paneCurrentMaskIndex[1]  = bottom.strokes.isEmpty ? 0 : 999

            isTracingLocked = false
        } else {
            paneCommittedCanvases[0].drawing = PKDrawing()
            paneCommittedCanvases[1].drawing = PKDrawing()
            paneIsCompleted      = [false, false]
            paneCurrentMaskIndex = [0, 0]
            isTracingLocked      = false
        }

        resetTransientLayer(paneIndex: 0)
        resetTransientLayer(paneIndex: 1)
        alphabetCollectionView.reloadData()
        updateNextChevronState()
    }

    private func onAllStrokesCompleted() {
        writingGameplayManager.saveTwoDrawings(
            top:    paneCommittedCanvases[0].drawing,
            bottom: paneCommittedCanvases[1].drawing,
            index:  currentIndex,
            category: categoryKey
        )
        writingGameplayManager.finalizeSession(
            index:       currentIndex,
            category:    categoryKey,
            mistakes:    writingGameplayManager.sessionMistakes,
            contentType: contentType
        )

        alphabetCollectionView.reloadData()
        nextChevronButton.isEnabled = true
        nextChevronButton.alpha     = 1.0
        traceCompleteButton.backgroundColor = .systemGreen
        
        // Guided Learning Path
        orchestrator?.recordLetterCompleted()
    }

    // MARK: - Actions
    @IBAction func traceCompleteTapped(_ sender: Any) {
        if paneShapeLayers[0].strokeColor == UIColor.red.cgColor ||
           paneShapeLayers[1].strokeColor == UIColor.red.cgColor { return }

        if isFullyCompleted { return }

        var didAdvanceAny = false
        if !paneIsCompleted[0], checkAndCommitGreenInk(paneIndex: 0) {
            didAdvanceAny = true
            resetTransientLayer(paneIndex: 0)
        }
        if !paneIsCompleted[1], checkAndCommitGreenInk(paneIndex: 1) {
            didAdvanceAny = true
            resetTransientLayer(paneIndex: 1)
        }

        if isFullyCompleted {
            let earnedSticker = writingGameplayManager.didEarnSticker()
            onAllStrokesCompleted()
            if earnedSticker { showStickerFromBottom(assetName: "sticker") }
            let delay: TimeInterval = earnedSticker ? 1.7 : 0.7
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.nextChevronTapped(self.nextChevronButton)
            }
        } else if !didAdvanceAny {
            flashIncompleteWarning()
        }
    }

    @IBAction func retryTapped(_ sender: UIButton) {
        switch (paneIsCompleted[0], paneIsCompleted[1]) {
        case (true, false):  resetPane(1)
        case (false, true):  resetPane(0)
        default:             resetPane(0); resetPane(1)
        }
        isTracingLocked = false
    }

    @IBAction func playTapped(_ sender: Any) { startTraceAnimationForPane0(force: false) }
    @IBAction func backTapped(_ sender: UIButton) { goBack() }
    @IBAction func homeTapped(_ sender: UIButton) { goHome() }

    @IBAction func nextChevronTapped(_ sender: UIButton) {
        guard let vc = storyboard!.instantiateViewController(withIdentifier: "SixLetterTraceVC") as? SixLetterTraceViewController else { return }
        vc.contentType        = contentType
        vc.currentLetterIndex = currentIndex
        vc.writingGameplayManager = writingGameplayManager
        navigationController?.pushViewController(vc, animated: false)
    }

    @IBAction func previousChevronTapped(_ sender: UIButton) {
        let targetIndex = currentIndex
        if let nav = navigationController,
           let prevVC = nav.viewControllers.dropLast().last as? OneLetterTraceViewController,
           prevVC.currentLetterIndex == targetIndex, prevVC.contentType == contentType {
            nav.popViewController(animated: false)
        } else {
            guard let vc = storyboard!.instantiateViewController(withIdentifier: "OneLetterTraceVC") as? OneLetterTraceViewController else { return }
            vc.contentType    = contentType
            vc.currentIndex   = targetIndex
            vc.writingGameplayManager = writingGameplayManager
            navigationController?.pushViewController(vc, animated: false)
        }
    }

    @IBAction func speakerButtonTapped(_ sender: Any) {
        let textToSpeak: String
        switch contentType {
        case .words:   preconditionFailure("Words not supported in TwoLetterTraceViewController")
        case .letters: textToSpeak = writingGameplayManager.getCharacterString(for: currentIndex, contentType: contentType)
        case .numbers: textToSpeak = "\(currentIndex)"
        }
        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        utterance.rate  = 0.5
        synthesizer.speak(utterance)
    }

    @IBAction func letterButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard writingGameplayManager.isIndexUnlocked(index: index, category: categoryKey) else { return }
        guard let vc = storyboard!.instantiateViewController(withIdentifier: "OneLetterTraceVC") as? OneLetterTraceViewController else { return }
        vc.contentType            = contentType
        vc.currentIndex           = index
        vc.writingGameplayManager = writingGameplayManager
        navigationController?.pushViewController(vc, animated: false)
    }

    // MARK: - Navigation Helpers
    func goHome() { navigationController?.popToRootViewController(animated: true) }

    func goBack() {
        guard let nav = navigationController else { return }
        for controller in nav.viewControllers {
            if String(describing: type(of: controller)).contains("WritingPreview") {
                nav.popToViewController(controller, animated: true)
                return
            }
        }
        nav.popViewController(animated: true)
    }

    private func flashIncompleteWarning() {
        let originalColor = traceCompleteButton.backgroundColor
        UIView.animate(withDuration: 0.1, animations: {
            self.traceCompleteButton.backgroundColor = .systemOrange
            self.traceCompleteButton.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.traceCompleteButton.backgroundColor = originalColor
                self.traceCompleteButton.transform = .identity
            }
        }
    }

    private func resetPane(_ index: Int) { resetPaneCompletely(index) }

    private func updateNextChevronState() {
        let unlocked = writingGameplayManager.getHighestUnlockedIndex(category: categoryKey)
        if currentIndex < unlocked {
            nextChevronButton.isEnabled = true
            nextChevronButton.alpha     = 1.0
            return
        }
        if let (top, bottom) = writingGameplayManager.loadTwoDrawings(index: currentIndex, category: categoryKey) {
            let isComplete = !top.strokes.isEmpty && !bottom.strokes.isEmpty
            nextChevronButton.isEnabled = isComplete
            nextChevronButton.alpha     = isComplete ? 1.0 : 0.4
        } else {
            nextChevronButton.isEnabled = false
            nextChevronButton.alpha     = 0.4
        }
    }

    // MARK: - CollectionView DataSource & Delegate
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch contentType {
        case .words:   preconditionFailure("Words not supported in TwoLetterTraceViewController")
        case .letters: return 52
        case .numbers: return 10
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "alphabet_cell", for: indexPath)
        guard let button = cell.contentView.subviews.first as? UIButton else { return cell }

        let itemIndex    = indexPath.item
        let titleString  = contentType == .letters
            ? writingGameplayManager.getCharacterString(for: itemIndex, contentType: contentType)
            : "\(itemIndex)"
        let unlockedIndex = writingGameplayManager.getHighestUnlockedIndex(category: categoryKey)
        let isUnlocked    = itemIndex <= unlockedIndex
        let isCompleted   = itemIndex < unlockedIndex

        cell.layer.borderWidth = 0
        cell.layer.borderColor = nil
        cell.backgroundColor   = isCompleted ? .systemGreen : (isUnlocked ? .systemBlue : .systemGray4)

        button.isEnabled = isUnlocked
        button.alpha     = isUnlocked ? 1.0 : 0.35

        var container = AttributeContainer()
        container.font            = UIFont(name: "ArialRoundedMTBold", size: 30)
        container.foregroundColor = isUnlocked ? .white : .systemGray2

        var config = button.configuration ?? UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(titleString, attributes: container)
        config.contentInsets   = .zero
        button.configuration   = config
        button.tag             = itemIndex

        button.removeTarget(nil, action: nil, for: .allEvents)
        button.addTarget(self, action: #selector(letterButtonTapped(_:)), for: .touchUpInside)

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let idx      = indexPath.item
        let unlocked = writingGameplayManager.getHighestUnlockedIndex(category: categoryKey)
        guard idx <= unlocked else { return }
        guard let vc = storyboard!.instantiateViewController(withIdentifier: "OneLetterTraceVC") as? OneLetterTraceViewController else { return }
        vc.contentType            = contentType
        vc.currentIndex           = idx
        vc.writingGameplayManager = writingGameplayManager
        navigationController?.pushViewController(vc, animated: false)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 60, height: 60)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        cell.layoutIfNeeded()
        cell.layer.cornerRadius = cell.bounds.height / 2
        cell.clipsToBounds      = true
    }
}
