import UIKit

final class ReadingPreviewViewController: UIViewController {

    // MARK: - Outlets
    @IBOutlet weak var cover4: UIImageView!
    @IBOutlet weak var cover3: UIImageView!
    @IBOutlet weak var card3bg_view: UIView!
    @IBOutlet weak var card4bg_view: UIView!
    @IBOutlet weak var title4: UILabel!
    @IBOutlet weak var title3: UILabel!
    @IBOutlet weak var title2: UILabel!
    @IBOutlet weak var title1: UILabel!
    @IBOutlet weak var card2bg_view: UIView!
    @IBOutlet weak var cover2: UIImageView!
    @IBOutlet weak var cover1: UIImageView!
    @IBOutlet weak var card1bg_view: UIView!
    @IBOutlet weak var prevLevelButton: UIButton!
    @IBOutlet weak var nextLevelButton: UIButton!
    @IBOutlet weak var levelLabel: UILabel!

    @IBOutlet weak var progress1: UIProgressView!
    @IBOutlet weak var progress2: UIProgressView!
    @IBOutlet weak var progress3: UIProgressView!
    @IBOutlet weak var progress4: UIProgressView!

    @IBOutlet weak var readButton4: UIButton!
    @IBOutlet weak var readButton3: UIButton!
    @IBOutlet weak var readButton2: UIButton!
    @IBOutlet weak var readButton1: UIButton!
    
    
    @IBOutlet var stackView1: UIView!
    @IBOutlet var stackView2: UIView!
    @IBOutlet var stackView3: UIView!
    @IBOutlet var stackView4: UIView!
    
    // MARK: - Injected
    var storyManager: StoryManager!
    var childManager: ChildManager!
    var checkpointHistoryManager: CheckpointHistoryManager!
    var skipManager: SkipManager!
    var orchestrator: SessionOrchestrator?   // injected by LearningPathHostVC when in guided mode

    private let difficultyLevels = ["Level 1", "Level 2", "Level 3"]

    private var levelStories: [Story] = []
    private var levelIndex = 0
    private var cardViews: [UIView] = []

    // MARK: - Glow Effect Properties
    private var idleTimer: Timer?
    private var glowStopTimer: Timer?

    private let initialIdleDelay: TimeInterval = 2
    private let glowDuration: TimeInterval = 4
    private let gapBetweenGlows: TimeInterval = 4

    private var highlightedIndexPath: IndexPath?

    // MARK: - Lifecycle
    private func verifyDependencies() {
        assert(storyManager != nil, "storyManager was not injected into \(type(of: self))")
        assert(childManager != nil, "childManager was not injected into \(type(of: self))")
        assert(checkpointHistoryManager != nil, "checkpointHistoryManager was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        cardViews = [card1bg_view, card2bg_view, card3bg_view, card4bg_view]
        styleCards()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        loadCurrentLevel()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startIdleTimer()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        idleTimer?.invalidate()
        glowStopTimer?.invalidate()
        cancelHighlight()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let buttons = [readButton1, readButton2, readButton3, readButton4]

        for button in buttons {
            button?.layer.cornerRadius = (button?.bounds.height ?? 0) / 2
            button?.clipsToBounds = true
        }
    }

    // MARK: - Level Handling
    private func loadCurrentLevel() {
        levelLabel.text = difficultyLevels[levelIndex]
       
        levelStories = storyManager.getStories(for: difficultyLevels[levelIndex])
        
        setupCards()
        updateChevronStates()
    }
    
    private func setupCards() {
        let covers = [cover1, cover2, cover3, cover4]
        let titles = [title1, title2, title3, title4]
        let backgrounds = [card1bg_view, card2bg_view, card3bg_view, card4bg_view]
        let progressViews = [progress1, progress2, progress3, progress4]
        let buttons = [readButton1, readButton2, readButton3, readButton4]
        
        // 👇 NEW: checkpoint stacks
        let checkpointStacks = [
            stackView1,
            stackView2,
            stackView3,
            stackView4
        ]
        
        for i in 0..<4 {
            guard let cover = covers[i],
                  let title = titles[i],
                  let bg = backgrounds[i],
                  let progress = progressViews[i],
                  let button = buttons[i] else { continue }
            
            if i < levelStories.count {
                let story = levelStories[i]
                
                bg.isHidden = false
                title.text = story.title
                cover.image = UIImage(named: story.coverImage)
                
                bg.layer.cornerRadius = 20
                cover.layer.cornerRadius = 20
                bg.layer.masksToBounds = false
                
                // EXISTING: button + progress logic
                updateReadButton(button: button, progressView: progress, story: story)
                
                // 👇 NEW: CHECKPOINT LOGIC
                if let container = checkpointStacks[i] {
                    let (savedIndex, isCompleted) = storyManager.getProgress(for: story.id)

                    configureCheckpoints(
                        container: container,
                        story: story,
                        currentPage: savedIndex,
                        isCompleted: isCompleted
                    )
                }
                
            } else {
                bg.isHidden = true
            }
        }
    }
    private func getCheckpointPositions(
        for story: Story,
        currentPage: Int
    ) -> [(position: Float, completed: Bool)] {

        let totalPages = Float(story.content.count)

        return story.content.compactMap { page -> (Float, Bool)? in
            guard page.checkAfter else { return nil }
            
            // Position along the bar
            let position = Float(page.pageNumber - 1) / (totalPages - 1)
            
            // Use StoryManager to check true completion in CoreData
            let isDone = storyManager.isCheckpointCompleted(storyId: story.id, checkpointText: page.text)
            
            return (position, isDone)
        }
    }
    
    private func updateChevronStates() {
        prevLevelButton.isEnabled = levelIndex > 0
        prevLevelButton.alpha = levelIndex > 0 ? 1.0 : 0.4
        
        nextLevelButton.isEnabled = levelIndex < difficultyLevels.count - 1
        nextLevelButton.alpha = levelIndex < difficultyLevels.count - 1 ? 1.0 : 0.4
    }

    private func updateReadButton(button: UIButton, progressView: UIProgressView, story: Story) {
        let (savedIndex, isCompleted) = storyManager.getProgress(for: story.id)
        let totalPages = max(1, story.content.count)
        let green = UIColor(red: 0.22, green: 0.73, blue: 0.35, alpha: 1)

        var title = "Read"
        var titleColor = UIColor.white
        
        button.configuration = nil
        button.layer.cornerRadius = button.bounds.height / 2
        button.layer.borderWidth = 0
        button.layer.borderColor = nil
        
        if isCompleted {
            title = "Read Again"
            titleColor = .black
            progressView.progress = 1.0
            progressView.isHidden = false
            button.backgroundColor = .white
            button.layer.borderWidth = 3
            button.layer.borderColor = green.cgColor
        }
        else if savedIndex > 0 {
            title = "Continue"
            progressView.progress = pageProgressRatio(currentPageIndex: savedIndex, totalPages: totalPages)
            progressView.isHidden = false
            button.backgroundColor = .systemBlue
        }
        else {
            title = "Read"
            progressView.progress = 0.0
            progressView.isHidden = true
            
            button.backgroundColor = green
        }

        let font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        let attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: font, .foregroundColor: titleColor]
        )

        button.setAttributedTitle(attributedTitle, for: .normal)
    }

    private func pageProgressRatio(currentPageIndex: Int, totalPages: Int) -> Float {
        guard totalPages > 1, currentPageIndex > 0 else { return 0 }
        let clampedIndex = min(max(currentPageIndex, 0), totalPages - 1)
        return Float(clampedIndex) / Float(totalPages - 1)
    }
    private func getCompletedCheckpoints(for story: Story) -> Int {
        return story.content.filter { page in
            page.checkAfter &&
            storyManager.isCheckpointCompleted(
                storyId: story.id,
                checkpointText: page.text
            )
        }.count
    }

    private func getTotalCheckpoints(for story: Story) -> Int {
        return story.content.filter { $0.checkAfter }.count
    }
    
    // MARK: - Glow Effect
    private func startIdleTimer() {

        idleTimer?.invalidate()

        idleTimer = Timer.scheduledTimer(
            withTimeInterval: initialIdleDelay,
            repeats: false
        ) { [weak self] _ in
            self?.startGlowCycle()
        }
    }
    
    private func startGlowCycle() {

        triggerHighlightIfNeeded()

        glowStopTimer?.invalidate()
        glowStopTimer = Timer.scheduledTimer(
            withTimeInterval: glowDuration,
            repeats: false
        ) { [weak self] _ in
            self?.stopGlowAndScheduleNext()
        }
    }
    
    private func triggerHighlightIfNeeded() {

        let difficulty = difficultyLevels[levelIndex]

        guard let index = storyManager.indexToHighlight(for: difficulty) else { return }

        highlightedIndexPath = IndexPath(item: index, section: 0)

        let targetView = cardViews[index]

        targetView.layoutIfNeeded()

        startGlowAnimation(on: targetView)
        startPopAnimation(on: targetView)
    }
    
    private func stopGlowAndScheduleNext() {

        cancelHighlight()

        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(
            withTimeInterval: gapBetweenGlows,
            repeats: false
        ) { [weak self] _ in
            self?.startGlowCycle()
        }
    }
    
    private func startGlowAnimation(on view: UIView) {

        view.layer.shadowColor = UIColor.systemYellow.cgColor
        view.layer.shadowRadius = 12
        view.layer.shadowOffset = .zero

        let anim = CABasicAnimation(keyPath: "shadowOpacity")
        anim.fromValue = 0
        anim.toValue = 0.9
        anim.duration = 1.0
        anim.autoreverses = true
        anim.repeatCount = .infinity

        view.layer.add(anim, forKey: "glow")
    }
    
    private func startPopAnimation(on view: UIView) {

        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 1
        anim.toValue = 1.04
        anim.duration = 1.0
        anim.autoreverses = true
        anim.repeatCount = .infinity

        view.layer.add(anim, forKey: "pop")
    }
    
    private func cancelHighlight() {

        if let index = highlightedIndexPath?.item {

            let view = cardViews[index]

            view.layer.removeAnimation(forKey: "glow")
            view.layer.removeAnimation(forKey: "pop")
        }

        highlightedIndexPath = nil
    }
    
    // MARK: - Navigation
        private func openStory(at index: Int) {
            guard index < levelStories.count,
                  let storyboard = storyboard else { return }
            
            let story = levelStories[index]
            
            let (savedIndex, isCompleted) = storyManager.getProgress(for: story.id)
            
            let pageIndex = isCompleted ? 0 : min(max(0, savedIndex), story.content.count - 1)
            let page = story.content[pageIndex]
            
            if let imageName = page.imageURL, !imageName.isEmpty {
                guard let vc = storyboard.instantiateViewController(withIdentifier: "ImageLabelReadingVC") as? ImageLabelReadingViewController else { return }
                vc.story = story
                vc.currentIndex = pageIndex
                vc.storyTextString = page.text
                vc.imageName = imageName
                vc.storyManager = storyManager
                vc.childManager = childManager
                vc.checkpointHistoryManager = checkpointHistoryManager
                vc.skipManager = skipManager
                vc.orchestrator = orchestrator   // pass through for guided learning
                navigationController?.pushViewController(vc, animated: true)
            } else {
                guard let vc = storyboard.instantiateViewController(withIdentifier: "LabelReadingVC") as? LabelReadingViewController else { return }
                vc.story = story
                vc.currentIndex = pageIndex
                vc.storyTextString = page.text
                vc.storyManager = storyManager
                vc.childManager = childManager
                vc.checkpointHistoryManager = checkpointHistoryManager
                vc.skipManager = skipManager
                vc.orchestrator = orchestrator   // pass through for guided learning
                navigationController?.pushViewController(vc, animated: true)
            }
        }

    // MARK: - Styling
    private func configureCheckpoints(
            container: UIView,
            story: Story,
            currentPage: Int,
            isCompleted: Bool
    ) {
        
        container.layoutIfNeeded()
        container.subviews.forEach { $0.removeFromSuperview() }
        container.clipsToBounds = false
        
        let checkpoints = getCheckpointPositions(
            for: story,
            currentPage: currentPage
        )
        
        let width = container.bounds.width
        let height: CGFloat = 12
        
        let padding: CGFloat = 30
        let usableWidth = width - (2 * padding)
        
        let green = UIColor(red: 0.22, green: 0.73, blue: 0.35, alpha: 1)
        let nextCheckpointGray = UIColor.systemGray4
        
        // 🔹 BASE LINE
        let baseLine = UIView(
            frame: CGRect(
                x: padding,
                y: height/2 - 2,
                width: usableWidth,
                height: 4
            )
        )
        baseLine.backgroundColor = UIColor.systemGray5
        container.addSubview(baseLine)
        
        // 🔹 CONTINUOUS PROGRESS (page-based)
        let totalPages = max(1, story.content.count)
        
        let progressRatio: CGFloat = isCompleted
        ? 1.0
        : CGFloat(pageProgressRatio(currentPageIndex: currentPage, totalPages: totalPages))
        
        let progressLine = UIView(
            frame: CGRect(
                x: padding,
                y: height/2 - 2,
                width: progressRatio * usableWidth,
                height: 4
            )
        )
        progressLine.backgroundColor = green
        container.addSubview(progressLine)
        
        // 🔹 NODES (milestones)
        let lastCompletedIndex = checkpoints.indices.last(where: { checkpoints[$0].completed })
        let nextIndex = checkpoints.firstIndex(where: { !$0.completed })
        
        for (index, checkpoint) in checkpoints.enumerated() {
            
            let x = padding + CGFloat(checkpoint.position) * usableWidth
            
            let node = UIView(
                frame: CGRect(x: x - 6, y: 0, width: 12, height: 12)
            )
            node.layer.cornerRadius = 6
            
            if checkpoint.completed {
                // ● Completed
                node.backgroundColor = green
            }
            else if index == nextIndex {
                // ◎ Next milestone (bullseye)
                node.backgroundColor = .clear
                node.layer.borderWidth = 2
                node.layer.borderColor = nextCheckpointGray.cgColor
                
                let innerDot = UIView(frame: CGRect(x: 3, y: 3, width: 6, height: 6))
                innerDot.layer.cornerRadius = 3
                innerDot.backgroundColor = nextCheckpointGray
                node.addSubview(innerDot)
            }
            else {
                // · Future
                node.backgroundColor = UIColor.systemGray4
                node.frame.size = CGSize(width: 8, height: 8)
                node.layer.cornerRadius = 4
                node.frame.origin.x = x - 4
                node.frame.origin.y = 2
            }
            
            container.addSubview(node)
            
            // 👇 NEW: Hovering Bullseye Logic
            if index == lastCompletedIndex || index == nextIndex {
                let isGrayscale = (index == nextIndex)
                let emojiImageView = UIImageView(image: getBullseyeImage(isGrayscale: isGrayscale))
                
                // Position it hovering perfectly above the node
                emojiImageView.frame = CGRect(
                    x: x - 10,   // Center it over the node (20 width / 2)
                    y: -22,      // Shift it up to hover above the bar
                    width: 20,
                    height: 20
                )
                
                container.addSubview(emojiImageView)
            }
        }
    }
    
    private func styleCards() {
        let borderColor = UIColor(
            red: 250/255,
            green: 239/255,
            blue: 184/255,
            alpha: 1
        ).cgColor

        styleCard(card1bg_view, cover: cover1, borderColor: borderColor)
        styleCard(card2bg_view, cover: cover2, borderColor: borderColor)
        styleCard(card3bg_view, cover: cover3, borderColor: borderColor)
        styleCard(card4bg_view, cover: cover4, borderColor: borderColor)
    }

    private func styleCard(_ background: UIView, cover: UIImageView, borderColor: CGColor) {
        background.layer.cornerRadius = 25
        background.layer.borderWidth = 7
        background.layer.borderColor = borderColor

        cover.layer.cornerRadius = 25
        cover.clipsToBounds = true
    }

    // MARK: - Actions
    @IBAction func prevLevelTapped(_ sender: UIButton) {
        guard levelIndex > 0 else { return }
        levelIndex -= 1
        loadCurrentLevel()
        animateLevelChange()
    }

    @IBAction func nextLevelTapped(_ sender: UIButton) {
        guard levelIndex < difficultyLevels.count - 1 else { return }
        levelIndex += 1
        loadCurrentLevel()
        animateLevelChange()
    }

    @IBAction func backToHomeTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction func readCard1Tapped(_ sender: UIButton) { openStory(at: 0) }
    @IBAction func readCard2Tapped(_ sender: UIButton) { openStory(at: 1) }
    @IBAction func readCard3Tapped(_ sender: UIButton) { openStory(at: 2) }
    @IBAction func readCard4Tapped(_ sender: UIButton) { openStory(at: 3) }

    private func animateLevelChange() {
        UIView.transition(
            with: view,
            duration: 0.25,
            options: .transitionCrossDissolve,
            animations: nil
        )
    }
    // MARK: - Hovering Emoji Helper
        private func getBullseyeImage(isGrayscale: Bool) -> UIImage? {
            let size = CGSize(width: 20, height: 20)
            UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
            
            let text = "🎯"
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14)]
            let stringSize = text.size(withAttributes: attributes)
            let rect = CGRect(
                x: (size.width - stringSize.width) / 2,
                y: (size.height - stringSize.height) / 2,
                width: stringSize.width,
                height: stringSize.height
            )
            text.draw(in: rect, withAttributes: attributes)
            
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            // If we don't need grayscale, just return the colorful emoji
            guard isGrayscale, let originalImage = image, let ciImage = CIImage(image: originalImage) else {
                return image
            }
            
            // Apply zero saturation for the grayscale look
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(0.0, forKey: kCIInputSaturationKey)
            
            let context = CIContext(options: nil)
            if let output = filter?.outputImage, let cgImage = context.createCGImage(output, from: output.extent) {
                return UIImage(cgImage: cgImage, scale: originalImage.scale, orientation: originalImage.imageOrientation)
            }
            
            return image
        }
}
