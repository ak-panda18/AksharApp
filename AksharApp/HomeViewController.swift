import UIKit

class HomeViewController: UIViewController {

    // MARK: - Outlets
    @IBOutlet weak var readingView: UIView!
    @IBOutlet weak var writingView: UIView!
    @IBOutlet weak var phonicsView: UIView!
    @IBOutlet weak var ocrView: UIView!
    @IBOutlet weak var analytics: UIButton!
    @IBOutlet var continueLabel: UILabel!
    @IBOutlet var subContinueLabel: UILabel!
    @IBOutlet var teddyImageView: UIImageView!
    @IBOutlet var chevronButton: UIButton!

    // MARK: - Injected
    var storyManager: StoryManager!
    var writingGameplayManager: WritingGameplayManager!
    var analyticsStore: AnalyticsStore!
    var childManager: ChildManager!
    var checkpointHistoryManager: CheckpointHistoryManager!
    var phonicsFlowManager: PhonicsFlowManager!
    var phonicsGameplayManager: PhonicsGameplayManager!
    var bundleDataLoader: BundleDataLoader!
    var ocrManager: OCRManager!
    var speechManager: SpeechManager!
    var speechRecognitionManager: SpeechRecognitionManager!
    var gameTimerManager: GameTimerManager!
    var profileStore: ProfileStore!

    // MARK: - Lifecycle
    private func verifyDependencies() {
        assert(storyManager != nil, "storyManager was not injected into \(type(of: self))")
        assert(writingGameplayManager != nil, "writingGameplayManager was not injected into \(type(of: self))")
        assert(analyticsStore != nil, "analyticsStore was not injected into \(type(of: self))")
        assert(childManager != nil, "childManager was not injected into \(type(of: self))")
        assert(checkpointHistoryManager != nil, "checkpointHistoryManager was not injected into \(type(of: self))")
        assert(phonicsFlowManager != nil, "phonicsFlowManager was not injected into \(type(of: self))")
        assert(phonicsGameplayManager != nil, "phonicsGameplayManager was not injected into \(type(of: self))")
        assert(bundleDataLoader != nil, "bundleDataLoader was not injected into \(type(of: self))")
        assert(ocrManager != nil, "ocrManager was not injected into \(type(of: self))")
        assert(speechManager != nil, "speechManager was not injected into \(type(of: self))")
        assert(speechRecognitionManager != nil, "speechRecognitionManager was not injected into \(type(of: self))")
        assert(gameTimerManager != nil, "gameTimerManager was not injected into \(type(of: self))")
        assert(profileStore != nil, "profileStore was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(profileImageChanged(_:)),
            name: .profileImageDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        updateDashboardState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Called here (not viewWillAppear / viewDidLayoutSubviews) because
        // setImage() on a UIButton triggers a layout pass.  Calling it during
        // viewDidLayoutSubviews creates an infinite loop that freezes the app.
        updateProfileButtonImage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        chevronButton.layer.borderWidth = 1.5
        chevronButton.layer.borderColor = UIColor.systemBrown.cgColor

        analytics.layer.cornerRadius  = analytics.bounds.height / 2
        analytics.layer.masksToBounds = true
    }

    // MARK: - Profile button image
//    @objc private func profileImageChanged(_ notification: Notification) {
//        guard let image = notification.object as? UIImage else { return }
//        analytics.setImage(image, for: .normal)
//        analytics.imageView?.contentMode = .scaleAspectFill
//    }
//
//    private func updateProfileButtonImage() {
//        if let imageData = childManager?.currentChild.profileImageData,
//           let image = UIImage(data: imageData) {
//            analytics.setImage(image, for: .normal)
//            analytics.imageView?.contentMode = .scaleAspectFill
//        }
//    }
    @objc private func profileImageChanged(_ notification: Notification) {
        updateProfileButtonImage()
    }

    private func updateProfileButtonImage() {

        let size = analytics.bounds.size
        analytics.layer.cornerRadius = size.width / 2
        analytics.clipsToBounds = true
        analytics.imageEdgeInsets = .zero
        analytics.contentEdgeInsets = .zero

        if let imageData = childManager?.currentChild.profileImageData,
           let image = UIImage(data: imageData) {

            // Pre-render a circular, aspect-fill-cropped thumbnail at exactly
            // the button's size.  UIButton's imageView does NOT honour
            // scaleAspectFill, so we bake the correct crop into the bitmap
            // itself — matching what the profile screen's UIImageView shows.
            let cropped = makeCircularThumbnail(image, size: size)

            analytics.setBackgroundImage(nil, for: .normal)
            analytics.setImage(cropped.withRenderingMode(.alwaysOriginal), for: .normal)
            analytics.contentHorizontalAlignment = .center
            analytics.contentVerticalAlignment   = .center
            analytics.imageView?.contentMode      = .scaleAspectFill

        } else {

            analytics.setImage(nil, for: .normal)
            analytics.setBackgroundImage(nil, for: .normal)

            let defaultImage = UIImage(systemName: "person.crop.circle.fill")
            analytics.setImage(defaultImage, for: .normal)
            analytics.tintColor              = UIColor.systemBrown
            analytics.imageView?.contentMode = .scaleAspectFit
        }
    }

    // MARK: - Image helpers
    // Renders `image` into a square bitmap of `size`, aspect-fill cropped,
    // then clips it to a circle.  The result looks identical to a UIImageView
    // with contentMode = .scaleAspectFill and a circular corner radius.
    private func makeCircularThumbnail(_ image: UIImage, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()

            // Aspect-fill: scale so the shorter dimension fills `size`
            let scale = max(size.width  / image.size.width,
                            size.height / image.size.height)
            let drawW = image.size.width  * scale
            let drawH = image.size.height * scale
            let drawX = (size.width  - drawW) / 2
            let drawY = (size.height - drawH) / 2
            image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        }
    }

    // MARK: - Setup
    private func setupUI() {
        let menuViews   = [readingView, writingView, phonicsView, ocrView]
        let brownBorder = UIColor.systemBrown.cgColor
        menuViews.forEach { view in
            view?.layer.cornerRadius = 25
            view?.layer.borderColor  = brownBorder
            view?.layer.borderWidth  = 2.0
        }
    }

    // MARK: - Dashboard Logic
    private func navigateToReading() {
        guard let (story, pageIndex, _) = storyManager.getLastActiveStory() else {
            performSegue(withIdentifier: "readingSegue", sender: nil)
            return
        }
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let previewVC = sb.instantiateViewController(withIdentifier: "ReadingPreviewVC")
                as? ReadingPreviewViewController else { return }
        previewVC.storyManager             = storyManager
        previewVC.childManager             = childManager
        previewVC.checkpointHistoryManager = checkpointHistoryManager

        let pageContent = story.content[pageIndex]
        let targetVC: UIViewController

        if let imgName = pageContent.imageURL, !imgName.isEmpty {
            guard let vc = sb.instantiateViewController(withIdentifier: "ImageLabelReadingVC")
                    as? ImageLabelReadingViewController else { return }
            vc.story                    = story
            vc.currentIndex             = pageIndex
            vc.storyTextString          = pageContent.text
            vc.imageName                = imgName
            vc.storyManager             = storyManager
            vc.childManager             = childManager
            vc.checkpointHistoryManager = checkpointHistoryManager
            targetVC = vc
        } else {
            guard let vc = sb.instantiateViewController(withIdentifier: "LabelReadingVC")
                    as? LabelReadingViewController else { return }
            vc.story                    = story
            vc.currentIndex             = pageIndex
            vc.storyTextString          = pageContent.text
            vc.storyManager             = storyManager
            vc.childManager             = childManager
            vc.checkpointHistoryManager = checkpointHistoryManager
            targetVC = vc
        }
        navigationController?.setViewControllers([self, previewVC, targetVC], animated: true)
    }

    private func navigateToWriting() {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let previewVC = sb.instantiateViewController(withIdentifier: "WritingPreviewVC")
                as? WritingPreviewViewController else { return }
        previewVC.writingGameplayManager = writingGameplayManager
        let newStack = previewVC.buildDeepLinkStack(startingWith: [self, previewVC])
        navigationController?.setViewControllers(newStack, animated: true)
    }

    private func updateDashboardState() {
        let lastModule = UserDefaults.standard.string(forKey: "LastActiveModule") ?? "reading"
        if lastModule == "reading" {
            teddyImageView.image = UIImage(named: "reader_teddy")
            if let (title, isNew) = storyManager.getLastActiveStoryDetails() {
                continueLabel.text    = isNew ? "Want to start reading?" : "Want to continue reading?"
                subContinueLabel.text = title
            } else {
                continueLabel.text    = "Want to start reading?"
                subContinueLabel.text = "Select a Story"
            }
        } else if lastModule == "writing" {
            teddyImageView.image  = UIImage(named: "writer_teddy")
            continueLabel.text    = "Want to continue tracing?"
            subContinueLabel.text = writingGameplayManager.getLastActiveItemDescription()
        }
    }

    // MARK: - Prepare for Segue
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

        if segue.identifier == "profileSegue" {
            if let profileVC = segue.destination as? Profile_ViewController {
                profileVC.analyticsStore           = analyticsStore
                profileVC.checkpointHistoryManager = checkpointHistoryManager
                profileVC.childManager             = childManager
                profileVC.profileStore             = profileStore
            }
        }

        if segue.identifier == "readingSegue" {
            UserDefaults.standard.set("reading", forKey: "LastActiveModule")
            if let vc = segue.destination as? ReadingPreviewViewController {
                vc.storyManager             = storyManager
                vc.childManager             = childManager
                vc.checkpointHistoryManager = checkpointHistoryManager
            }
        } else if segue.identifier == "writingSegue" {
            UserDefaults.standard.set("writing", forKey: "LastActiveModule")
            if let vc = segue.destination as? WritingPreviewViewController {
                vc.writingGameplayManager = writingGameplayManager
            }
        } else if segue.identifier == "spinWheelSegue" {
            if let vc = segue.destination as? SpinWheelViewController {
                vc.phonicsFlowManager       = phonicsFlowManager
                vc.phonicsGameplayManager   = phonicsGameplayManager
                vc.bundleDataLoader         = bundleDataLoader
                vc.speechManager            = speechManager
                vc.speechRecognitionManager = speechRecognitionManager
                vc.gameTimerManager         = gameTimerManager
            }
        } else if segue.identifier == "ocrSegue" {
            if let vc = segue.destination as? UploadsViewController {
                vc.ocrManager               = ocrManager
                vc.storyManager             = storyManager
                vc.childManager             = childManager
                vc.checkpointHistoryManager = checkpointHistoryManager
            }
        }
    }

    // MARK: - Actions
    @IBAction func phonicsTapped(_ sender: UITapGestureRecognizer) {
        performSegue(withIdentifier: "spinWheelSegue", sender: nil)
    }
    @IBAction func readingTapped(_ sender: UITapGestureRecognizer) {
        performSegue(withIdentifier: "readingSegue", sender: nil)
    }
    @IBAction func writingTapped(_ sender: UITapGestureRecognizer) {
        performSegue(withIdentifier: "writingSegue", sender: nil)
    }
    @IBAction func ocrTapped(_ sender: UITapGestureRecognizer) {
        performSegue(withIdentifier: "ocrSegue", sender: nil)
    }
    @IBAction func continueTapped(_ sender: UIButton) {
        let lastModule = UserDefaults.standard.string(forKey: "LastActiveModule") ?? "reading"
        if lastModule == "reading" { navigateToReading() } else { navigateToWriting() }
    }
}
