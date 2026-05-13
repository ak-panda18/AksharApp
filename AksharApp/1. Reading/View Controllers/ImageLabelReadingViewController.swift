import UIKit
import AVFoundation

class ImageLabelReadingViewController: UIViewController, AVSpeechSynthesizerDelegate {

    @IBOutlet weak var speakerButton: UIButton!
    @IBOutlet weak var StoryCollectionView: UICollectionView!
    @IBOutlet weak var previousButton: UIButton!
    @IBOutlet weak var storyTitleLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var retakeButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!

    // MARK: - Properties
    var readingSession: ReadingSessionData?

    // MARK: - Injected
    var storyManager: StoryManager!
    var childManager: ChildManager!
    var checkpointHistoryManager: CheckpointHistoryManager!

    var story: Story!
    var currentIndex: Int = 0
    var storyTextString: String = ""
    var imageName: String?
    private var syllablePopover: UILabel?
    private var syllableOverlay: UIView?
    let speechSynthesizer = AVSpeechSynthesizer()
    var isSpeakingFromButton = false
    private var isRestartingSpeech = false

    // MARK: - Lifecycle
    private func verifyDependencies() {
        assert(storyManager != nil, "storyManager was not injected into \(type(of: self))")
        assert(childManager != nil, "childManager was not injected into \(type(of: self))")
        assert(checkpointHistoryManager != nil, "checkpointHistoryManager was not injected into \(type(of: self))")
        assert(story != nil, "story was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        let brownColor = UIColor(red: 128/255, green: 87/255, blue: 55/255, alpha: 1.0)
        speakerButton.layer.borderColor = brownColor.cgColor
        speakerButton.layer.borderWidth = 3.0
        setSpeakerIcon()
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        speakerButton.addGestureRecognizer(longPress)
        StoryCollectionView.dataSource = self
        StoryCollectionView.delegate   = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        storyTitleLabel?.text = story.title
        storyManager.saveProgress(storyId: story.id, pageIndex: currentIndex)
        navigationController?.setNavigationBarHidden(true, animated: false)
        StoryCollectionView.reloadData()
        updateProgress()
        updateChevronEnabledState()
        updateRetakeButtonVisibility()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startReadingSessionIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        endReadingSessionIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        speakerButton.layer.cornerRadius = speakerButton.bounds.height / 2
        speakerButton.clipsToBounds = true
        guard let layout = StoryCollectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        layout.invalidateLayout()
        StoryCollectionView.layoutIfNeeded()
        let indexPath = IndexPath(item: 0, section: 0)
        guard let attributes = layout.layoutAttributesForItem(at: indexPath) else { return }
        let cellHeight      = attributes.frame.height
        let availableHeight = StoryCollectionView.bounds.height
        let inset = max(0, (availableHeight - cellHeight) / 2.0)
        StoryCollectionView.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
    }

    // MARK: - IB Actions
    @IBAction func retakeCheckpointButton(_ sender: UIButton) {
        _ = navigateToCheckpoint(nextIndex: currentIndex + 1, forceRetake: true)
    }

    @IBAction func speakerButtonTapped(_ sender: UIButton) {
        if speechSynthesizer.isPaused {
            speechSynthesizer.continueSpeaking(); showPauseIcon(); isSpeakingFromButton = true; return
        }
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.pauseSpeaking(at: .immediate); showSpeakerIcon(); isSpeakingFromButton = false; return
        }
        let utterance = AVSpeechUtterance(string: storyTextString)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        utterance.rate  = 0.35
        speechSynthesizer.delegate = self
        speechSynthesizer.speak(utterance)
        showPauseIcon()
        isSpeakingFromButton = true
    }

    @IBAction func homeTapped(_ sender: UIButton) {
        endReadingSessionIfNeeded()
        guard let nav = navigationController else { return }
        if let homeVC = nav.viewControllers.first { nav.setViewControllers([homeVC], animated: true) }
    }

    @IBAction func previousTapped(_ sender: UIButton) { goToPage(offset: -1); stopSpeechIfNeeded() }
    @IBAction func nextTapped(_ sender: UIButton)     { goToPage(offset: 1);  stopSpeechIfNeeded() }

    @IBAction func backToPreviewTapped(_ sender: UIButton) { popToReadingPreview() }

    private func setSpeakerIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        speakerButton.setImage(UIImage(systemName: "speaker.wave.2.fill", withConfiguration: config), for: .normal)
    }
    private func showPauseIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        speakerButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
    }
    func showSpeakerIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        speakerButton.setImage(UIImage(systemName: "speaker.wave.2.fill", withConfiguration: config), for: .normal)
    }
    private func stopSpeechIfNeeded() {
        if speechSynthesizer.isSpeaking || speechSynthesizer.isPaused {
            speechSynthesizer.stopSpeaking(at: .immediate)
            showSpeakerIcon()
            isSpeakingFromButton = false
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { showRestartPopup() }
    }
    @objc private func restartTapped() {
        view.viewWithTag(999)?.removeFromSuperview()
        isRestartingSpeech = true
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: storyTextString)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-AU")
        utterance.rate  = 0.35
        speechSynthesizer.delegate = self
        speechSynthesizer.speak(utterance)
        showPauseIcon()
        isSpeakingFromButton = true
    }
    private func showRestartPopup() {
        view.viewWithTag(999)?.removeFromSuperview()
        let popup = UIButton(); popup.tag = 999
        popup.setTitle("Restart", for: .normal)
        popup.setTitleColor(UIColor(red: 128/255, green: 87/255, blue: 55/255, alpha: 1), for: .normal)
        popup.titleLabel?.font    = .systemFont(ofSize: 22, weight: .bold)
        popup.backgroundColor     = .systemBackground
        popup.layer.cornerRadius  = 14
        popup.layer.borderWidth   = 3
        popup.layer.borderColor   = speakerButton.layer.borderColor
        popup.layer.shadowColor   = UIColor.black.cgColor
        popup.layer.shadowOpacity = 0.2
        popup.layer.shadowOffset  = CGSize(width: 0, height: 2)
        popup.layer.shadowRadius  = 6
        popup.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)
        let bf = speakerButton.convert(speakerButton.bounds, to: view)
        popup.frame = CGRect(x: bf.midX - 60, y: bf.minY - 50, width: 120, height: 44)
        view.addSubview(popup)
    }
}

// MARK: - Data Source
extension ImageLabelReadingViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "story_cell", for: indexPath)
                as? ImageLabelCollectionViewCell else { return UICollectionViewCell() }
        cell.storyText.text          = storyTextString
        cell.storyText.font          = fontForStory()
        cell.storyText.textAlignment = .left
        cell.storyText.numberOfLines = 0
        cell.storyImage.image = imageName.flatMap { UIImage(named: $0) }
        cell.storyText.isUserInteractionEnabled = true
        cell.storyText.gestureRecognizers?.forEach { cell.storyText.removeGestureRecognizer($0) }
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLabelLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        cell.storyText.addGestureRecognizer(longPress)
        return cell
    }
}

// MARK: - Flow Layout Delegate
extension ImageLabelReadingViewController: UICollectionViewDelegateFlowLayout {
    private func naturalCellHeight(for width: CGFloat) -> CGFloat {
        let sidePadding: CGFloat = 40
        let topPadding:  CGFloat = 40
        let gap:         CGFloat = 24
        let imageHeight: CGFloat = 652.5
        let bottomPadding: CGFloat = 40
        let textWidth = width - sidePadding * 2.5
        let font      = fontForStory()
        let boundingRect = (storyTextString as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font], context: nil)
        return topPadding + ceil(boundingRect.height) + 40 + gap + imageHeight + bottomPadding
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let horizontalMargin: CGFloat = 49
        let cardWidth = collectionView.bounds.width - horizontalMargin * 2
        return CGSize(width: cardWidth, height: naturalCellHeight(for: cardWidth))
    }
}

// MARK: - Reading Session
private extension ImageLabelReadingViewController {
    func startReadingSessionIfNeeded() {
        guard readingSession == nil else { return }
        readingSession = storyManager.startReadingSession(
            storyId: story.id,
            childId: childManager.currentChild.id?.uuidString ?? "default",
            level: extractLevel(from: story.difficulty)
        )
    }

    func endReadingSessionIfNeeded() {
        guard let session = readingSession, session.endTime == nil else { return }
        storyManager.endReadingSession(session)
        readingSession?.endTime = Date()
    }

    func extractLevel(from difficulty: String) -> Int {
        switch difficulty.lowercased() {
        case "level 1": return 1
        case "level 2": return 2
        case "level 3": return 3
        default: return 1
        }
    }
}

// MARK: - Navigation
private extension ImageLabelReadingViewController {
    private func showStoryPage(at index: Int) {
        let pages = story.content
        let page  = pages[index]
        guard let storyboard else { return }
        let nextVC: UIViewController
        if let imgName = page.imageURL, !imgName.isEmpty {
            guard let vc = storyboard.instantiateViewController(withIdentifier: "ImageLabelReadingVC")
                    as? ImageLabelReadingViewController else { return }
            vc.story = story; vc.currentIndex = index; vc.storyTextString = page.text
            vc.imageName = imgName; vc.readingSession = readingSession
            vc.storyManager = storyManager; 
            vc.childManager = childManager; vc.checkpointHistoryManager = checkpointHistoryManager
            nextVC = vc
        } else {
            guard let vc = storyboard.instantiateViewController(withIdentifier: "LabelReadingVC")
                    as? LabelReadingViewController else { return }
            vc.story = story; vc.currentIndex = index; vc.storyTextString = page.text
            vc.readingSession = readingSession
            vc.storyManager = storyManager; 
            vc.childManager = childManager; vc.checkpointHistoryManager = checkpointHistoryManager
            nextVC = vc
        }
        if let nav = navigationController {
            var stack = nav.viewControllers; stack[stack.count - 1] = nextVC
            nav.setViewControllers(stack, animated: false)
        }
    }

    func goToPage(offset: Int) {
        let totalCount = story?.content.count ?? 0
        let newIndex   = currentIndex + offset
        if offset < 0 {
            if newIndex < 0 { navigationController?.popViewController(animated: true); return }
            showStoryPage(at: newIndex); return
        }
        if let story {
            let currentPage = story.content[currentIndex]
            if currentPage.checkAfter && !isCurrentCheckpointCompleted() {
                if navigateToCheckpoint(nextIndex: newIndex) { return }
            }
        }
        if newIndex >= totalCount {
            if let s = story { storyManager.saveProgress(storyId: s.id, pageIndex: currentIndex, didComplete: true) }
            popToReadingPreview(); return
        }
        showStoryPage(at: newIndex)
    }

    func popToReadingPreview() {
        endReadingSessionIfNeeded()
        guard let nav = navigationController else { return }
        for vc in nav.viewControllers {
            if vc is ReadingPreviewViewController { nav.popToViewController(vc, animated: true); return }
        }
        nav.popToRootViewController(animated: true)
    }
}

// MARK: - Checkpoint Logic
private extension ImageLabelReadingViewController {
    func navigateToCheckpoint(nextIndex: Int, forceRetake: Bool = false) -> Bool {
        guard let currentStory = story else { return false }
        let currentPageNumber  = currentStory.content[currentIndex].pageNumber
        guard let item = storyManager.getCheckpointItem(storyId: currentStory.id, pageNumber: currentPageNumber) else { return false }
        guard let storyboard,
              let cpVC = storyboard.instantiateViewController(withIdentifier: "CheckpointVC") as? CheckpointViewController
        else { return false }
        cpVC.story = currentStory; cpVC.checkpointItem = item; cpVC.nextPageIndex = nextIndex
        cpVC.fallbackPageIndex = firstPageAfterLastCheckpoint(currentIndex: currentIndex)
        cpVC.forceRetake = forceRetake; cpVC.readingSession = self.readingSession
        cpVC.modalPresentationStyle = .fullScreen
        cpVC.storyManager = storyManager; 
        cpVC.childManager = childManager; cpVC.checkpointHistoryManager = checkpointHistoryManager
        navigationController?.pushViewController(cpVC, animated: true)
        return true
    }

    func isCurrentCheckpointCompleted() -> Bool {
        guard let story else { return false }
        let currentPage = story.content[currentIndex]
        guard currentPage.checkAfter else { return false }
        guard let item = storyManager.getCheckpointItem(storyId: story.id, pageNumber: currentPage.pageNumber) else { return false }
        return storyManager.isCheckpointCompleted(storyId: story.id, checkpointText: item.text)
    }

    func updateRetakeButtonVisibility() {
        guard let story = story else { retakeButton?.isHidden = true; return }
        let currentPage = story.content[currentIndex]
        
        // ONLY show if this page is a checkpoint AND it is already completed
        if currentPage.checkAfter && isCurrentCheckpointCompleted() {
            retakeButton?.isHidden = false
        } else {
            retakeButton?.isHidden = true
        }
    }

    func firstPageAfterLastCheckpoint(currentIndex: Int) -> Int {
        let pages = story.content
        for i in stride(from: currentIndex - 1, through: 0, by: -1) {
            if pages[i].checkAfter { return i + 1 }
        }
        return 0
    }
}

// MARK: - UI Updates & Progress
private extension ImageLabelReadingViewController {
    func updateProgress() {
        let totalPages = story.content.count
        guard totalPages > 0 else { progressView?.progress = 0; return }
        progressView.progress = Float(currentIndex + 1) / Float(totalPages)
    }

    func updateChevronEnabledState() {
        previousButton.isEnabled = currentIndex > 0
        let totalCount = story?.content.count ?? 0
        if currentIndex < totalCount - 1 {
            nextButton.isEnabled = true
        } else {
            nextButton.isEnabled = !isCurrentCheckpointCompleted()
        }
    }
}

// MARK: - Text & Font
private extension ImageLabelReadingViewController {
    func fontForStory() -> UIFont {
        switch story.difficulty.lowercased() {
        case "level 1": return UIFont(name: "ArialMT",           size: 28) ?? UIFont.systemFont(ofSize: 28)
        case "level 2": return UIFont(name: "TrebuchetMS",       size: 28) ?? UIFont.systemFont(ofSize: 28)
        case "level 3": return UIFont(name: "TimesNewRomanPSMT", size: 28) ?? UIFont.systemFont(ofSize: 28)
        default:        return UIFont.systemFont(ofSize: 28)
        }
    }
}

// MARK: - Syllable Interaction
private extension ImageLabelReadingViewController {
    @objc func handleLabelLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let label = recognizer.view as? UILabel else { return }
        let pointInLabel = recognizer.location(in: label)
        guard let (word, wordRectInLabel) = wordAtPoint(in: label, point: pointInLabel) else { return }
        showSyllablePopover(text: PhonemeEngine.kindleSplit(word), from: label, wordRectInLabel: wordRectInLabel)
    }

    @objc func handleOverlayTap(_ recognizer: UITapGestureRecognizer) {
        guard let overlay = syllableOverlay, let pop = syllablePopover else { return }
        if !pop.frame.contains(recognizer.location(in: overlay)) {
            pop.removeFromSuperview(); overlay.removeFromSuperview()
            syllablePopover = nil; syllableOverlay = nil
        }
    }

    func showSyllablePopover(text: String, from label: UILabel, wordRectInLabel: CGRect) {
        syllablePopover?.removeFromSuperview(); syllableOverlay?.removeFromSuperview()
        syllablePopover = nil; syllableOverlay = nil

        let overlay = UIView(frame: view.bounds); overlay.backgroundColor = .clear
        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleOverlayTap(_:))))
        view.addSubview(overlay); syllableOverlay = overlay

        let popLabel = UILabel()
        popLabel.text = text; popLabel.font = label.font.withSize(30)
        popLabel.textColor = .white; popLabel.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        popLabel.numberOfLines = 0; popLabel.textAlignment = .center
        popLabel.layer.cornerRadius = 10; popLabel.clipsToBounds = true
        let maxWidth    = view.bounds.width - 40
        let fittingSize = popLabel.sizeThatFits(CGSize(width: maxWidth - 24, height: .greatestFiniteMagnitude))
        popLabel.frame.size = CGSize(width: fittingSize.width + 24, height: fittingSize.height + 16)
        let wordRectInView = label.convert(wordRectInLabel, to: overlay)
        var originX = wordRectInView.midX - popLabel.frame.width / 2
        originX = max(8, min(originX, overlay.bounds.width - popLabel.frame.width - 8))
        popLabel.frame.origin = CGPoint(x: originX, y: max(8, wordRectInView.minY - popLabel.frame.height - 8))
        overlay.addSubview(popLabel); syllablePopover = popLabel
    }

    func wordAtPoint(in label: UILabel, point: CGPoint) -> (word: String, rect: CGRect)? {
        let attributedText: NSAttributedString
        if let attr = label.attributedText { attributedText = attr }
        else if let text = label.text { attributedText = NSAttributedString(string: text, attributes: [.font: label.font as Any]) }
        else { return nil }
        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager(); textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: label.bounds.size)
        textContainer.lineFragmentPadding = 0; textContainer.maximumNumberOfLines = label.numberOfLines
        textContainer.lineBreakMode = label.lineBreakMode; layoutManager.addTextContainer(textContainer)
        var fraction: CGFloat = 0
        let glyphIndex     = layoutManager.glyphIndex(for: point, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        if characterIndex >= textStorage.length { return nil }
        let string     = attributedText.string as NSString
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var start = characterIndex, end = characterIndex
        while start > 0 { let c = string.character(at: start - 1); if separators.contains(UnicodeScalar(c)!) { break }; start -= 1 }
        while end < string.length { let c = string.character(at: end); if separators.contains(UnicodeScalar(c)!) { break }; end += 1 }
        let range = NSRange(location: start, length: end - start)
        if range.length == 0 { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return (string.substring(with: range), layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer))
    }
}

extension ImageLabelReadingViewController {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if isRestartingSpeech { isRestartingSpeech = false; return }
        showSpeakerIcon(); isSpeakingFromButton = false
    }
}
