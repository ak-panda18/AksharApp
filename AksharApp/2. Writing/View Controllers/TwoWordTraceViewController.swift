import UIKit
import PencilKit
import AVFoundation

class TwoWordTraceViewController: BaseTraceViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    // MARK: - Properties
    var selectedCategory: TracingCategory = .threeLetter
    var currentWordIndex: Int {
        get { return currentIndex }
        set { currentIndex = newValue }
    }
    
    override var categoryKey: String {
        return selectedCategory.rawValue
    }
    
    override var brushWidth: CGFloat {
        get {
            switch selectedCategory {
            case .threeLetter: return 32.0
            case .fourLetter: return 27.0
            case .fiveLetter: return 22.0
            case .sixLetter: return 17.0
            case .power: return 15.0
            }
        }
        set { super.brushWidth = newValue }
    }
    
    private var words: [TracingWord] = []
    private var analyticsSessionID: UUID!
    private var didSetupAfterLayout = false

    // MARK: - Outlets
    @IBOutlet weak var yellowView: UIView!
    @IBOutlet weak var speakerButton: UIView!
    @IBOutlet weak var wordsCollectionView: UICollectionView!
    @IBOutlet weak var backChevronButton: UIButton!
    
    // MARK: - Pane Views
    @IBOutlet weak var topLetterImageView: UIImageView!
    @IBOutlet weak var topCommittedDrawingImageView: UIImageView!
    @IBOutlet weak var topTransientDrawingImageView: UIImageView!

    @IBOutlet weak var bottomLetterImageView: UIImageView!
    @IBOutlet weak var bottomCommittedDrawingImageView: UIImageView!
    @IBOutlet weak var bottomTransientDrawingImageView: UIImageView!
    
    @IBOutlet weak var nextChevronButton: UIButton!
    @IBOutlet weak var traceCompleteButton: UIButton!
    @IBOutlet weak var retryButton: UIButton!
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        analyticsSessionID = UUID()
        initPaneArrays(count: 2)
        
        paneLetterImageViews = [topLetterImageView, bottomLetterImageView]
        
        setupShapeLayer(for: topLetterImageView)
        setupShapeLayer(for: bottomLetterImageView)
        
        let topCanvas = setupCanvas(in: topCommittedDrawingImageView)
        let bottomCanvas = setupCanvas(in: bottomCommittedDrawingImageView)
        paneCommittedCanvases = [topCanvas, bottomCanvas]
        
        setupUIAppearance()
        setupCollectionView()
        loadWordsData()
        
        loadWord(at: currentWordIndex)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNextChevronState()
        wordsCollectionView.reloadData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        savePartialProgressIfNeeded()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if paneShapeLayers.indices.contains(1) {
            paneShapeLayers[0].frame = topLetterImageView.bounds
            paneShapeLayers[1].frame = bottomLetterImageView.bounds
        }
    }
    
    // MARK: - Setup
    private func loadWordsData() {
        let allWords = TracingWordLoader.loadWords()
        words = allWords.words(for: selectedCategory.rawValue)
    }

    private func setupCollectionView() {
        wordsCollectionView.delegate = self
        wordsCollectionView.dataSource = self
        
        if let layout = wordsCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.estimatedItemSize = .zero
            layout.minimumInteritemSpacing = 4
            layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
            layout.scrollDirection = .horizontal
        }
    }
    
    private func setupUIAppearance() {

        applyBorderStyle(to: speakerButton, borderColor: themeBrown)
        applyBorderStyle(to: retryButton, borderColor: themeBrown)
        applyBorderStyle(to: traceCompleteButton, borderColor: themeBrown)

        applyBorderStyle(
            to: wordsCollectionView,
            borderColor: themeYellow,
            borderWidth: 2,
            cornerRadius: 20
        )

        yellowView.layer.cornerRadius = 25
        retryButton.isHidden = false

        nextChevronButton.isEnabled = false
        nextChevronButton.alpha = 0.4

        topLetterImageView.isUserInteractionEnabled = false
        bottomLetterImageView.isUserInteractionEnabled = false
        topCommittedDrawingImageView.isUserInteractionEnabled = false
        bottomCommittedDrawingImageView.isUserInteractionEnabled = false
    }


    // MARK: - Word Loading
    private func loadWord(at index: Int) {
        guard index < words.count else { return }
        currentWordIndex = index
        let category = categoryKey
        
        let word = words[index]
        if let image = UIImage(named: word.wordImageName) {
            topLetterImageView.image = image
            bottomLetterImageView.image = image
        }
        
        let maskName = "\(word.wordImageName)_mask"
        paneMaskAssetNames = [maskName]
        
        loadMasks(forPane: 0, assetNames: [maskName])
        loadMasks(forPane: 1, assetNames: [maskName])
        
        restoreTwoWordDrawings(
            index: index,
            category: category
        )
        resetTransientLayer(paneIndex: 0)
        resetTransientLayer(paneIndex: 1)
        
        wordsCollectionView.reloadData()
        updateNextChevronState()
        
        let allDone = paneIsCompleted[0] && paneIsCompleted[1]
        traceCompleteButton.backgroundColor = allDone ? .systemGreen : .white
    }
    
    private func restoreTwoWordDrawings(
        index: Int,
        category: String
    ) {

        if let (top, bottom) =
            writingGameplayManager
            .loadTwoDrawings(index: index, category: category) {

            paneCommittedCanvases[0].drawing = top
            paneCommittedCanvases[1].drawing = bottom

            paneIsCompleted[0] = !top.strokes.isEmpty
            paneIsCompleted[1] = !bottom.strokes.isEmpty

            paneCurrentMaskIndex[0] = paneIsCompleted[0] ? 999 : 0
            paneCurrentMaskIndex[1] = paneIsCompleted[1] ? 999 : 0

            isTracingLocked = false

        } else {

            paneCommittedCanvases[0].drawing = PKDrawing()
            paneCommittedCanvases[1].drawing = PKDrawing()

            paneIsCompleted = [false, false]
            paneCurrentMaskIndex = [0, 0]
            isTracingLocked = false
        }
    }

    private func onAllStrokesCompleted() {
        writingGameplayManager.saveTwoDrawings(
            top: paneCommittedCanvases[0].drawing,
            bottom: paneCommittedCanvases[1].drawing,
            index: currentWordIndex,
            category: categoryKey
        )
        writingGameplayManager.finalizeSession(
            index: currentIndex,
            category: categoryKey,
            mistakes: writingGameplayManager.sessionMistakes,
            contentType: .words,
            tracingCategory: selectedCategory
        )
        
        nextChevronButton.isEnabled = true
        nextChevronButton.alpha = 1.0
        traceCompleteButton.backgroundColor = .systemGreen
        
        writingGameplayManager.saveMistakeCount(0, index: currentWordIndex, category: categoryKey)
    }

    // MARK: - Actions
    @IBAction func traceCompleteTapped(_ sender: Any) {
        if paneShapeLayers[0].strokeColor == UIColor.red.cgColor ||
           paneShapeLayers[1].strokeColor == UIColor.red.cgColor {
            return
        }
        
        var didAdvanceTop = false
        var didAdvanceBottom = false
        
        if !paneIsCompleted[0] {
            didAdvanceTop = checkAndCommitGreenInk(paneIndex: 0)
        }
        
        if !paneIsCompleted[1] {
            didAdvanceBottom = checkAndCommitGreenInk(paneIndex: 1)
        }
        
        let topDone = paneIsCompleted[0]
        let bottomDone = paneIsCompleted[1]
        if !didAdvanceTop && !didAdvanceBottom {
            if !(topDone && bottomDone) {
                flashIncompleteWarning()
            }
        }
        
        if didAdvanceTop || didAdvanceBottom {
            savePartialProgressIfNeeded()
        }
        
        if topDone && bottomDone {
            onAllStrokesCompleted()
            let earnedSticker = writingGameplayManager.didEarnSticker()
            if earnedSticker { showStickerFromBottom(assetName: "sticker") }
            let delay: TimeInterval = earnedSticker ? 1.7 : 0.7
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.nextChevronTapped(self.nextChevronButton)
            }
        }
    }
    
    @IBAction func retryTapped(_ sender: UIButton) {
        let topCompleted = paneIsCompleted[0]
        let bottomCompleted = paneIsCompleted[1]
        switch (topCompleted, bottomCompleted) {
        case (true, false):
            resetPane(1)
        case (false, true):
            resetPane(0)
        case (true, true), (false, false):
            resetPane(0)
            resetPane(1)
            traceCompleteButton.backgroundColor = .white
        }
        isTracingLocked = false
    }
    
    private func resetPane(_ index: Int) {
        resetPaneCompletely(index)
    }

    @IBAction func backButtonTapped(_ sender: Any) {
        if let nav = navigationController {
            for controller in nav.viewControllers {
                if String(describing: type(of: controller)).contains("WordsCategories") {
                    nav.popToViewController(controller, animated: true)
                    return
                }
            }
            nav.popViewController(animated: true)
        }
    }

    @IBAction func homeButtonTapped(_ sender: UIButton) {
        navigationController?.popToRootViewController(animated: true)
    }
    
    @IBAction func backTapped(_ sender: UIButton) {
            guard let vc = storyboard!.instantiateViewController(withIdentifier: "OneWordTraceVC") as? OneWordTraceViewController else { return }
            vc.currentWordIndex = currentWordIndex
            vc.selectedCategory = selectedCategory
            vc.writingGameplayManager = writingGameplayManager
            navigationController?.pushViewController(vc, animated: false)
        }
    
    @IBAction func nextChevronTapped(_ sender: UIButton) {
            guard let vc = storyboard!.instantiateViewController(withIdentifier: "SixWordTraceVC") as? SixWordTraceViewController else { return }
            vc.currentWordIndex = currentWordIndex
            vc.selectedCategory = selectedCategory
            vc.writingGameplayManager = writingGameplayManager
            navigationController?.pushViewController(vc, animated: false)
        }

    @IBAction func speakerTapped(_ sender: Any) {
        guard currentWordIndex < words.count else { return }
        let word = words[currentWordIndex].word
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
    
    // MARK: - Helpers
    private func updateNextChevronState() {
        let unlocked = writingGameplayManager.getHighestUnlockedIndex(category: categoryKey)
        
        if currentWordIndex < unlocked {
            nextChevronButton.isEnabled = true
            nextChevronButton.alpha = 1.0
            return
        }
        
        if let (top, bottom) = writingGameplayManager.loadTwoDrawings(index: currentWordIndex, category: categoryKey) {
             let isComplete = !top.strokes.isEmpty && !bottom.strokes.isEmpty
             nextChevronButton.isEnabled = isComplete
             nextChevronButton.alpha = isComplete ? 1.0 : 0.4
        } else {
             nextChevronButton.isEnabled = false
             nextChevronButton.alpha = 0.4
        }
    }
    
    private func savePartialProgressIfNeeded() {
        let topHas = !paneCommittedCanvases[0].drawing.strokes.isEmpty
        let bottomHas = !paneCommittedCanvases[1].drawing.strokes.isEmpty
        
        if topHas || bottomHas {
            writingGameplayManager.saveTwoDrawings(
                top: paneCommittedCanvases[0].drawing,
                bottom: paneCommittedCanvases[1].drawing,
                index: currentWordIndex,
                category: categoryKey
            )
        }
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

    // MARK: - CollectionView DataSource & Delegate
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return words.count
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "wordButtonCell",
                                                      for: indexPath)
        
        guard let button = cell.viewWithTag(100) as? UIButton else {
            return cell
        }
        
        let word = words[indexPath.item].word
        
        button.configuration = nil
        button.setTitle(word, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 30, weight: .medium)
        
        let unlockedIdx = writingGameplayManager
            .getHighestUnlockedIndex(category: categoryKey)
        
        let isUnlocked = indexPath.item <= unlockedIdx
        let isCompleted = indexPath.item < unlockedIdx
        
        if isCompleted {
            button.backgroundColor = .systemGreen
            button.setTitleColor(.white, for: .normal)
            button.alpha = 1.0
            
        } else if isUnlocked {
            button.backgroundColor = .systemBlue
            button.setTitleColor(.white, for: .normal)
            button.alpha = 1.0
            
        } else {
            button.backgroundColor = .systemGray4
            button.setTitleColor(.systemGray2, for: .normal)
            button.alpha = 0.35
        }
        
        if indexPath.item == currentWordIndex {
            button.layer.borderWidth = 3
            button.layer.borderColor = UIColor.white.cgColor
        } else {
            button.layer.borderWidth = 0
        }
        button.layoutIfNeeded()
        button.layer.cornerRadius = button.bounds.height / 2
        button.clipsToBounds = true
        button.isUserInteractionEnabled = false
        
        return cell
    }
    
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            let unlockedIdx = writingGameplayManager.getHighestUnlockedIndex(category: categoryKey)
            
            if indexPath.item <= unlockedIdx {
                guard let vc = storyboard!.instantiateViewController(withIdentifier: "OneWordTraceVC") as? OneWordTraceViewController else { return }
                vc.currentWordIndex = indexPath.item
                vc.selectedCategory = selectedCategory
                vc.writingGameplayManager = writingGameplayManager
                navigationController?.pushViewController(vc, animated: false)
            }
        }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let word = words[indexPath.item].word
        let font = UIFont.systemFont(ofSize: 30, weight: .medium)
        let textSize = (word as NSString).size(withAttributes: [.font: font])
        return CGSize(width: max(textSize.width + 32, 100), height: textSize.height + 24)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 4
    }
}
