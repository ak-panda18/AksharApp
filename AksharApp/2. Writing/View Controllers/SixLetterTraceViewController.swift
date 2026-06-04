import UIKit
import PencilKit
import AVFoundation

class SixLetterTraceViewController: BaseTraceViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    // MARK: - Properties
    var currentLetterIndex: Int {
        get { return currentIndex }
        set { currentIndex = newValue }
    }
    
    override var traceStage: String { return "six" }
    
    // MARK: - Outlets: General
    @IBOutlet weak var yellowView: UIView!
    @IBOutlet weak var speakerButton: UIView!
    @IBOutlet weak var alphabetCollectionView: UICollectionView!
    @IBOutlet weak var traceCompleteButton: UIButton!
    @IBOutlet weak var retryButton: UIButton!
    @IBOutlet weak var backChevronButton: UIButton!
    @IBOutlet weak var nextChevronButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    
    // MARK: - Outlets: Panes (1-6)
    @IBOutlet weak var pane1LetterImageView: UIImageView!
    @IBOutlet weak var pane1CommittedDrawingImageView: UIImageView!
    @IBOutlet weak var pane1TransientDrawingImageView: UIImageView!

    @IBOutlet weak var pane2LetterImageView: UIImageView!
    @IBOutlet weak var pane2CommittedDrawingImageView: UIImageView!
    @IBOutlet weak var pane2TransientDrawingImageView: UIImageView!

    @IBOutlet weak var pane3LetterImageView: UIImageView!
    @IBOutlet weak var pane3CommittedDrawingImageView: UIImageView!
    @IBOutlet weak var pane3TransientDrawingImageView: UIImageView!

    @IBOutlet weak var pane4LetterImageView: UIImageView!
    @IBOutlet weak var pane4CommittedDrawingImageView: UIImageView!
    @IBOutlet weak var pane4TransientDrawingImageView: UIImageView!

    @IBOutlet weak var pane5LetterImageView: UIImageView!
    @IBOutlet weak var pane5CommittedDrawingImageView: UIImageView!
    @IBOutlet weak var pane5TransientDrawingImageView: UIImageView!

    @IBOutlet weak var pane6LetterImageView: UIImageView!
    @IBOutlet weak var pane6CommittedDrawingImageView: UIImageView!
    @IBOutlet weak var pane6TransientDrawingImageView: UIImageView!

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.brushWidth = 20.0
        writingGameplayManager.startNewSession()
        
        initPaneArrays(count: 6)
        
        paneLetterImageViews = [
            pane1LetterImageView, pane2LetterImageView, pane3LetterImageView,
            pane4LetterImageView, pane5LetterImageView, pane6LetterImageView
        ]
        
        if let pane1Container = pane1LetterImageView.superview {
            pane1Container.layer.zPosition = 10
            
            if let parentContainer = pane1Container.superview, parentContainer != yellowView, parentContainer != self.view {
                parentContainer.layer.zPosition = 10
            }
        }
        
        let committedImageViews = [
            pane1CommittedDrawingImageView, pane2CommittedDrawingImageView, pane3CommittedDrawingImageView,
            pane4CommittedDrawingImageView, pane5CommittedDrawingImageView, pane6CommittedDrawingImageView
        ]
        
        for i in 0..<6 {
            setupShapeLayer(for: paneLetterImageViews[i])
            let canvas = setupCanvas(in: committedImageViews[i]!)
            paneCommittedCanvases.append(canvas)
        }
        
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

        applyBorderStyle(
            to: alphabetCollectionView,
            borderColor: themeYellow,
            borderWidth: 2,
            cornerRadius: 20
        )
        
        yellowView.layer.cornerRadius = 25
        retryButton.isHidden = false
        
        nextChevronButton.isEnabled = false
        nextChevronButton.alpha = 0.4
        speakerButton.isUserInteractionEnabled = true
        
        for iv in paneLetterImageViews { iv.isUserInteractionEnabled = false }
    }

    // MARK: - Content Loading
    private func showLetter(at index: Int) {
        currentIndex = index
        let contentProvider = TraceContentProvider(writingGameplayManager: writingGameplayManager)
        let (paneImages, maskNames) = contentProvider.paneImages(index: index, contentType: contentType)
        for i in 0..<6 {
            paneLetterImageViews[i].image = paneImages[i]
            loadMasks(forPane: i, assetNames: maskNames)
        }

        restoreSavedDrawings()

        alphabetCollectionView.reloadData()
        updateNextChevronState()
    }

    
    private func restoreSavedDrawings() {

        if let saved = writingGameplayManager
            .loadSixDrawings(index: currentIndex, category: categoryKey),
           saved.count == 6 {

            for i in 0..<6 {
                paneCommittedCanvases[i].drawing = saved[i]

                let hasStrokes = !saved[i].strokes.isEmpty
                paneIsCompleted[i] = hasStrokes
                paneCurrentMaskIndex[i] = hasStrokes ? 999 : 0
            }

        } else {
            resetAllPanes()
        }

        isTracingLocked = false
    }

    private func resetAllPanes() {
        for i in 0..<6 {
            resetPaneCompletely(i)
        }
    }

    private func startTraceAnimationForCurrent(force: Bool = false) {
            
            if !force {
                if paneIsCompleted[0] { return }
                
                let unlocked = writingGameplayManager.getHighestUnlockedIndex(category: categoryKey)
                if currentIndex < unlocked { return }
            }
            
            let letterChar = writingGameplayManager.getCharacterString(
            for: currentIndex,
            contentType: contentType
            )
            
            playTraceAnimation(at: 0, for: letterChar)
        }
    
    private func onAllStrokesCompleted() {
        let drawings = paneCommittedCanvases.map { $0.drawing }
        writingGameplayManager.saveSixDrawings(drawings, index: currentIndex, category: categoryKey)
        writingGameplayManager.finalizeSession(
            index: currentIndex,
            category: categoryKey,
            mistakes: writingGameplayManager.sessionMistakes,
            contentType: contentType
        )

        alphabetCollectionView.reloadData()
        nextChevronButton.isEnabled = true
        nextChevronButton.alpha = 1.0
        isTracingLocked = true
        
        // Guided Learning Path
        orchestrator?.recordLetterCompleted()
    }

    // MARK: - Actions
    @IBAction func traceCompleteTapped(_ sender: Any) {
            for i in 0..<6 {
                if paneShapeLayers[i].strokeColor == UIColor.red.cgColor { return }
            }
            
            if paneIsCompleted.allSatisfy({ $0 }) { return }

            var didAdvanceAny = false
            for i in 0..<6 {
                if !paneIsCompleted[i] {
                    if checkAndCommitGreenInk(paneIndex: i) {
                        didAdvanceAny = true
                        resetTransientLayer(paneIndex: i)
                    }
                }
            }
            
            if paneIsCompleted.allSatisfy({ $0 }) {

                let earnedSticker = writingGameplayManager.didEarnSticker()

                onAllStrokesCompleted()

                if earnedSticker {
                    showStickerFromBottom(assetName: "sticker")
                }

                let delay: TimeInterval = earnedSticker ? 1.7 : 0.7

                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.nextChevronTapped(self.nextChevronButton)
                }

            } else if !didAdvanceAny {
                flashIncompleteWarning()
            }
    }
    @IBAction func playTapped(_ sender: Any) {
        startTraceAnimationForPane0(force: false)
    }
    
    @IBAction func retryTapped(_ sender: UIButton) {
        let completedCount = paneIsCompleted.filter { $0 }.count

        if completedCount > 0 && completedCount < 6 {
            for i in 0..<6 where !paneIsCompleted[i] {
                resetPane(i)
            }
        } else {
            for i in 0..<6 {
                resetPane(i)
            }
        }
        isTracingLocked = false
    }
    
    private func resetPane(_ index: Int) {
        resetPaneCompletely(index)
    }
    
    @IBAction func backTapped(_ sender: UIButton) { goBack() }
    @IBAction func homeTapped(_ sender: UIButton) { goHome() }
    
    @IBAction func nextChevronTapped(_ sender: UIButton) {
            guard let vc = storyboard!.instantiateViewController(withIdentifier: "OneLetterTraceVC") as? OneLetterTraceViewController else { return }
            vc.contentType = contentType
            vc.currentLetterIndex = currentLetterIndex + 1
            vc.writingGameplayManager = writingGameplayManager
            navigationController?.pushViewController(vc, animated: false)
        }
    
    @IBAction func previousChevrontapped(_ sender: UIButton) {
            let targetIndex = currentIndex
            if let nav = navigationController,
               let prevVC = nav.viewControllers.dropLast().last as? TwoLetterTraceViewController,
               prevVC.currentLetterIndex == targetIndex,
               prevVC.contentType == self.contentType {
                nav.popViewController(animated: false)
            } else {
                guard let vc = storyboard!.instantiateViewController(withIdentifier: "TwoLetterTraceVC") as? TwoLetterTraceViewController else { return }
                vc.contentType = contentType
                vc.currentIndex = targetIndex
                vc.writingGameplayManager = writingGameplayManager
                navigationController?.pushViewController(vc, animated: false)
            }
        }
    
    @IBAction func speakerButtonTapped(_ sender: UIButton) {
        let textToSpeak: String
        switch contentType {
        case .words: fatalError("Words not supported in OneLetterTraceViewController")
        case .letters:
            textToSpeak = writingGameplayManager.getCharacterString(
                for: currentIndex,
                contentType: contentType
            )
        case .numbers:
            textToSpeak = "\(currentIndex)"
        }
        
        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
    
    @IBAction func letterButtonTapped(_ sender: UIButton) {
            let index = sender.tag
            guard writingGameplayManager.isIndexUnlocked(
                index: index,
                category: categoryKey
            ) else { return }

            guard let vc = storyboard!.instantiateViewController(withIdentifier: "OneLetterTraceVC") as? OneLetterTraceViewController else { return }
            vc.contentType = contentType
            vc.currentIndex = index
            vc.writingGameplayManager = writingGameplayManager
            navigationController?.pushViewController(vc, animated: false)
        }

    // MARK: - Navigation Helpers
    func goHome() {
        navigationController?.popToRootViewController(animated: true)
    }

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
    
    private func updateNextChevronState() {
        let unlocked = writingGameplayManager.getHighestUnlockedIndex(category: categoryKey)
        if currentIndex < unlocked {
            nextChevronButton.isEnabled = true
            nextChevronButton.alpha = 1.0
            return
        }
        if let drawings = writingGameplayManager.loadSixDrawings(index: currentIndex, category: categoryKey) {
             let isComplete = drawings.allSatisfy { !$0.strokes.isEmpty }
             nextChevronButton.isEnabled = isComplete
             nextChevronButton.alpha = isComplete ? 1.0 : 0.4
        } else {
             nextChevronButton.isEnabled = false
             nextChevronButton.alpha = 0.4
        }
    }

    // MARK: - CollectionView DataSource & Delegate
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch contentType {
        case .words: fatalError("Words not supported in OneLetterTraceViewController")
        case .letters: return 52
        case .numbers: return 10
        }
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "alphabet_cell",
                                                      for: indexPath)
        
        guard let button = cell.contentView.subviews.first as? UIButton else {
            return cell
        }
        
        let itemIndex = indexPath.item
        
        let titleString: String
        if contentType == .letters {
            titleString = writingGameplayManager.getCharacterString(
                for: itemIndex,
                contentType: contentType
            )
        } else {
            titleString = "\(itemIndex)"
        }
        
        let unlockedIndex = writingGameplayManager
            .getHighestUnlockedIndex(category: categoryKey)
        
        let isUnlocked = itemIndex <= unlockedIndex
        let isCompleted = itemIndex < unlockedIndex
        
        cell.layer.borderWidth = 0
        cell.layer.borderColor = nil
        
        if isCompleted {
            cell.backgroundColor = .systemGreen
            button.isEnabled = true
            button.alpha = 1.0
            
        } else if isUnlocked {
            cell.backgroundColor = .systemBlue
            button.isEnabled = true
            button.alpha = 1.0
            
        } else {
            cell.backgroundColor = .systemGray4
            button.isEnabled = false
            button.alpha = 0.35
        }
        
        var container = AttributeContainer()
        container.font = UIFont(name: "ArialRoundedMTBold", size: 30)
        container.foregroundColor = isUnlocked ? .white : .systemGray2
        
        var config = button.configuration ?? UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(titleString, attributes: container)
        config.contentInsets = .zero
        button.configuration = config
        
        button.tag = itemIndex
        
        button.removeTarget(nil, action: nil, for: .allEvents)
        button.addTarget(self,
                         action: #selector(letterButtonTapped(_:)),
                         for: .touchUpInside)
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            let idx = indexPath.item
            let unlocked = writingGameplayManager.getHighestUnlockedIndex(category: categoryKey)
            guard idx <= unlocked else { return }
            
            guard let vc = storyboard!.instantiateViewController(withIdentifier: "OneLetterTraceVC") as? OneLetterTraceViewController else { return }
            vc.contentType = contentType
            vc.currentIndex = idx
            vc.writingGameplayManager = writingGameplayManager
            navigationController?.pushViewController(vc, animated: false)
        }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 60, height: 60)
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath){
        cell.layoutIfNeeded()
        cell.layer.cornerRadius = cell.bounds.height / 2
        cell.clipsToBounds = true
    }
}
