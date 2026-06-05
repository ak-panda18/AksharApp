import UIKit

class SpinWheelViewController: UIViewController {

    @IBOutlet var wheelView: UIView!
    //@IBOutlet var gameCardViews: [UIView]!
    //@IBOutlet weak var rectangularBackground: UIImageView!
    @IBOutlet var chooseYourOwnView: UIView!
    
    // MARK: - Injected
    var phonicsFlowManager: PhonicsFlowManager!
    var phonicsGameplayManager: PhonicsGameplayManager!
    var bundleDataLoader: BundleDataLoader!
    var speechManager: SpeechManager!
    var speechRecognitionManager: SpeechRecognitionManager!
    var gameTimerManager: GameTimerManager!
    var writingGameplayManager: WritingGameplayManager!
    
    // Guided Learning Path
    weak var sessionDelegate: AnyObject? // Since AksharActivityDelegate is not defined, using AnyObject?
    var orchestrator: SessionOrchestrator?


    private var pointerLayer: CALayer?
    private var tapTextLayer: CATextLayer?
    private var selectedExercise: ExerciseType!
    private let goldColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0).cgColor
    private let paleYellowColor = UIColor(red: 250/255, green: 239/255, blue: 184/255, alpha: 1).cgColor

    private var rimLayer: CAShapeLayer?
    private var isSpinning = false
    //private var manualModeUnlocked = false
   // private var boardLockOverlay: UIView?

    private func verifyDependencies() {
            assert(phonicsFlowManager != nil, "phonicsFlowManager was not injected into \(type(of: self))")
            assert(phonicsGameplayManager != nil, "phonicsGameplayManager was not injected into \(type(of: self))")
            assert(bundleDataLoader != nil, "bundleDataLoader was not injected into \(type(of: self))")
            assert(speechManager != nil, "speechManager was not injected into \(type(of: self))")
            assert(speechRecognitionManager != nil, "speechRecognitionManager was not injected into \(type(of: self))")
            assert(gameTimerManager != nil, "gameTimerManager was not injected into \(type(of: self))")
            
            // Add this new line:
//            assert(writingGameplayManager != nil, "writingGameplayManager was not injected into \(type(of: self))")
        }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        setupChooseYourOwnView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        wheelView.layer.shadowColor = goldColor
        wheelView.layer.shadowOpacity = 0.25
        wheelView.layer.shadowRadius = 20
        wheelView.layer.shadowOffset = CGSize(width: 0, height: 12)
        wheelView.layer.shadowRadius = 35
        wheelView.layer.masksToBounds = false

        drawWheel()
        drawPointer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let tap = UITapGestureRecognizer(target: self, action: #selector(wheelTapped))
        wheelView.addGestureRecognizer(tap)
        wheelView.isUserInteractionEnabled = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resetWheelInteraction()
    }

    // MARK: - Wheel Tap
    @objc private func wheelTapped() {
        guard !isSpinning else { return }
        isSpinning = true
        
        chooseYourOwnView.isUserInteractionEnabled = false
        chooseYourOwnView.alpha = 0.5

        tapTextLayer?.removeFromSuperlayer()
        tapTextLayer = nil
        stopIdleAnimations()
        spinWheel()
    }

    // MARK: - Navigation
    private func goToCover() {
        let sb = UIStoryboard(name: "Main", bundle: nil)

        guard let coverVC = sb.instantiateViewController(
            withIdentifier: "PhonicsCoverVC"
        ) as? PhonicsCoverViewController else { return }

        coverVC.chosenExercise           = selectedExercise
        coverVC.phonicsGameplayManager   = phonicsGameplayManager
        coverVC.bundleDataLoader         = bundleDataLoader
        coverVC.speechManager            = speechManager
        coverVC.speechRecognitionManager = speechRecognitionManager
        coverVC.gameTimerManager         = gameTimerManager

        navigationController?.pushViewController(coverVC, animated: true)
    }

    private func resetWheelInteraction() {
        isSpinning = false
        
        chooseYourOwnView.isUserInteractionEnabled = true
        chooseYourOwnView.alpha = 1.0
        wheelView.isUserInteractionEnabled = true
        startIdleAnimations()
    }

    // MARK: - Game Cards
    private func setupChooseYourOwnView() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(chooseYourOwnTapped))
        chooseYourOwnView.addGestureRecognizer(tap)
        chooseYourOwnView.isUserInteractionEnabled = true
    }

    @objc private func chooseYourOwnTapped() {
        // This immediately brings up the PIN gate
        showParentGate()
    }
    
//    private func setupGameCards() {
//        let exercises = ExerciseType.allCases
//
//        let colors: [UIColor] = [
//            UIColor(red: 1.00, green: 0.92, blue: 0.60, alpha: 1),
//            UIColor(red: 0.85, green: 0.75, blue: 0.95, alpha: 1),
//            UIColor(red: 0.68, green: 0.85, blue: 0.95, alpha: 1),
//            UIColor(red: 0.75, green: 0.90, blue: 0.75, alpha: 1),
//            UIColor(red: 1.00, green: 0.70, blue: 0.70, alpha: 1)
//        ]
//
//        for (index, card) in gameCardViews.enumerated() {
//            card.backgroundColor = colors[index]
//            card.layer.cornerRadius = 18
//            card.clipsToBounds = true
//            card.layer.borderWidth = 2
//            card.layer.borderColor = UIColor(red: 198/255, green: 134/255, blue: 45/255, alpha: 1).cgColor
//
//            card.subviews.forEach { $0.removeFromSuperview() }
//
//            let label = UILabel()
//            label.text = exercises[index].titleText
//            label.textAlignment = .center
//            label.textColor = .brown
//            label.font = UIFont(name: "Arial Rounded MT Bold", size: 20)
//            label.numberOfLines = 2
//            label.translatesAutoresizingMaskIntoConstraints = false
//            card.addSubview(label)
//
//            NSLayoutConstraint.activate([
//                label.centerXAnchor.constraint(equalTo: card.centerXAnchor),
//                label.centerYAnchor.constraint(equalTo: card.centerYAnchor),
//                label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
//                label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6)
//            ])
//
//            card.tag = index
//
//            let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:)))
//            card.addGestureRecognizer(tap)
//            card.isUserInteractionEnabled = true
//        }
//    }
//    
//    private func lockBoard() {
//
//        guard let boardContainer = rectangularBackground.superview else { return }
//
//        boardContainer.bringSubviewToFront(rectangularBackground)
//
//        let lockImage = UIImageView(image: UIImage(systemName: "lock.fill"))
//        lockImage.tintColor = .brown
//        lockImage.translatesAutoresizingMaskIntoConstraints = false
//        lockImage.contentMode = .scaleAspectFit
//
//        rectangularBackground.addSubview(lockImage)
//
//        NSLayoutConstraint.activate([
//            lockImage.centerXAnchor.constraint(equalTo: rectangularBackground.centerXAnchor),
//            lockImage.centerYAnchor.constraint(equalTo: rectangularBackground.centerYAnchor),
//            lockImage.widthAnchor.constraint(equalToConstant: 55),
//            lockImage.heightAnchor.constraint(equalToConstant: 55)
//        ])
//
//        rectangularBackground.isUserInteractionEnabled = true
//
//        let tap = UITapGestureRecognizer(target: self, action: #selector(boardLockedTapped))
//        rectangularBackground.addGestureRecognizer(tap)
//    }
//
//    private func setGameCardsEnabled(_ enabled: Bool) {
//        for card in gameCardViews {
//            card.isUserInteractionEnabled = enabled
//            card.alpha = enabled ? 1.0 : 0.5
//        }
//    }
//    
//    @objc private func boardLockedTapped() {
//        if !manualModeUnlocked {
//            showParentGate()
//        }
//    }
    
    private func shakeView(_ view: UIView) {

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [-12, 12, -10, 10, -6, 6, -3, 3, 0]
        animation.duration = 0.4
        animation.timingFunction = CAMediaTimingFunction(name: .linear)

        view.layer.add(animation, forKey: "shake")
    }
    
    @objc private func handleOverlayTap(_ sender: UITapGestureRecognizer) {

        guard let overlay = sender.view else { return }

        let location = sender.location(in: overlay)

        if let card = overlay.subviews.first {
            if !card.frame.contains(location) {
                overlay.removeFromSuperview()
            }
        }
    }
    
    private func showParentGate() {

        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 32
        card.layer.borderWidth = 3
        card.layer.borderColor = UIColor.systemYellow.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Parent Permission Required"
        title.font = UIFont(name: "ArialRoundedMTBold", size: 23)
        title.textColor = .brown
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let question = UILabel()
        question.text = "What is 12 × 2 ?"
        question.font = UIFont.systemFont(ofSize: 22, weight: .medium)
        question.textAlignment = .center
        question.translatesAutoresizingMaskIntoConstraints = false

        let field = UITextField()
        field.borderStyle = .roundedRect
        field.keyboardType = .numberPad
        field.translatesAutoresizingMaskIntoConstraints = false

        let unlockButton = UIButton(type: .system)
        unlockButton.setTitle("Unlock", for: .normal)
        unlockButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 20)
        unlockButton.translatesAutoresizingMaskIntoConstraints = false

        unlockButton.addAction(UIAction { _ in

            if field.text == "24" {
                overlay.removeFromSuperview()
                self.navigateToWordsCategories()
            } else {
                self.shakeView(field)
                field.text = ""
            }

        }, for: .touchUpInside)

        card.addSubview(title)
        card.addSubview(question)
        card.addSubview(field)
        card.addSubview(unlockButton)

        overlay.addSubview(card)
        view.addSubview(overlay)
        
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(handleOverlayTap(_:)))
        overlay.addGestureRecognizer(dismissTap)

        NSLayoutConstraint.activate([

            card.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 400),
            card.heightAnchor.constraint(equalToConstant: 260),

            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 35),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            question.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
            question.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 30),
            question.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -30),

            field.topAnchor.constraint(equalTo: question.bottomAnchor, constant: 26),
            field.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            field.widthAnchor.constraint(equalToConstant: 160),

            unlockButton.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 28),
            unlockButton.centerXAnchor.constraint(equalTo: card.centerXAnchor)
        ])
    }

//    @objc private func cardTapped(_ sender: UITapGestureRecognizer) {
//
//        guard manualModeUnlocked else {
//            showParentGate()
//            return
//        }
//
//        guard let view = sender.view else { return }
//        selectedExercise = ExerciseType.allCases[view.tag]
//        goToCover()
//    }

    // MARK: - Spin
    private func spinWheel() {
        selectedExercise = phonicsFlowManager.getCurrentExercise()

        let sliceCount = ExerciseType.allCases.count
        let sliceAngle = (2 * CGFloat.pi) / CGFloat(sliceCount)
        let index = ExerciseType.allCases.firstIndex(of: selectedExercise)!

        let sliceCenterAngle = (sliceAngle * CGFloat(index)) + (sliceAngle / 2)
        let landingAlignment = -sliceCenterAngle
        let totalSpins = CGFloat(-3) * CGFloat.pi * 2
        let finalAngle = totalSpins + landingAlignment

        rimLayer?.shadowRadius = 45
        rimLayer?.shadowOpacity = 1.0

        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = finalAngle
        animation.duration = 2
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        wheelView.layer.add(animation, forKey: "spinAnimation")

        let tickAnim = CABasicAnimation(keyPath: "transform.rotation.z")
        tickAnim.fromValue = -0.05
        tickAnim.toValue = 0.05
        tickAnim.duration = 0.08
        tickAnim.autoreverses = true
        tickAnim.repeatCount = 25
        pointerLayer?.add(tickAnim, forKey: "tickAnimation")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.wheelView.transform = CGAffineTransform(rotationAngle: finalAngle)
            self.wheelView.layer.removeAllAnimations()
            self.pointerLayer?.removeAnimation(forKey: "tickAnimation")

            UIView.animate(withDuration: 0.15, animations: {
                self.pointerLayer?.transform = CATransform3DMakeRotation(-0.15, 0, 0, 1)
            }, completion: { _ in
                UIView.animate(withDuration: 0.15) {
                    self.pointerLayer?.transform = CATransform3DIdentity
                }
            })

            self.phonicsFlowManager.advance()
            
            self.orchestrator?.recordPhonicsRoundCompleted()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.goToCover()
            }
        }

        UIView.animate(withDuration: 0.3, delay: 0, options: [.autoreverse], animations: {
            self.wheelView.transform = self.wheelView.transform.scaledBy(x: 1.05, y: 1.05)
        })
    }

    // MARK: - Draw Wheel
    private func drawWheel() {
        wheelView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let diameter = wheelView.bounds.width
        let radius = diameter / 2
        let center = CGPoint(x: wheelView.bounds.midX, y: wheelView.bounds.midY)

        wheelView.layer.cornerRadius = radius
        wheelView.clipsToBounds = false
        wheelView.layer.borderWidth = 0

        let exercises = ExerciseType.allCases
        let sliceAngle = (2 * CGFloat.pi) / CGFloat(exercises.count)

        let colors: [UIColor] = [
            UIColor(red: 1.00, green: 0.92, blue: 0.60, alpha: 1),
            UIColor(red: 0.85, green: 0.75, blue: 0.95, alpha: 1),
            UIColor(red: 0.68, green: 0.85, blue: 0.95, alpha: 1),
            UIColor(red: 0.75, green: 0.90, blue: 0.75, alpha: 1),
            UIColor(red: 1.00, green: 0.70, blue: 0.70, alpha: 1)
        ]

        for i in 0..<exercises.count {
            let startAngle = sliceAngle * CGFloat(i)
            let endAngle = startAngle + sliceAngle

            let path = UIBezierPath()
            path.move(to: center)
            path.addArc(withCenter: center, radius: radius,
                        startAngle: startAngle, endAngle: endAngle, clockwise: true)
            path.close()

            let sliceLayer = CAShapeLayer()
            sliceLayer.path = path.cgPath
            sliceLayer.fillColor = colors[i % colors.count].cgColor
            sliceLayer.strokeColor = goldColor
            sliceLayer.lineWidth = 1.0
            wheelView.layer.addSublayer(sliceLayer)

            let textLayer = CATextLayer()
            textLayer.string = exercises[i].titleText
            let uiFont = UIFont(name: "Arial Rounded MT Bold", size: 20)!
            textLayer.font = CGFont(uiFont.fontName as CFString)
            textLayer.fontSize = uiFont.pointSize
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = UIColor.brown.cgColor
            textLayer.contentsScale = traitCollection.displayScale

            let textAngle = startAngle + sliceAngle / 2
            let textRadius = radius * 0.62
            let textX = center.x + textRadius * cos(textAngle)
            let textY = center.y + textRadius * sin(textAngle)

            let text = exercises[i].titleText as NSString
            let size = text.size(withAttributes: [.font: uiFont])

            textLayer.frame = CGRect(x: textX - size.width/2, y: textY - size.height/2,
                                     width: size.width, height: size.height)
            textLayer.transform = CATransform3DMakeRotation(textAngle, 0, 0, 1)
            wheelView.layer.addSublayer(textLayer)
        }

        rimLayer?.removeFromSuperlayer()
        let newRimLayer = CAShapeLayer()
        newRimLayer.path = UIBezierPath(ovalIn: wheelView.bounds).cgPath
        newRimLayer.strokeColor = goldColor
        newRimLayer.fillColor = UIColor.clear.cgColor
        newRimLayer.lineWidth = 8
        newRimLayer.shadowColor = goldColor
        newRimLayer.shadowOffset = .zero
        newRimLayer.shadowRadius = 18
        newRimLayer.shadowOpacity = 0.6
        wheelView.layer.addSublayer(newRimLayer)
        self.rimLayer = newRimLayer

        addCenterHubWithText()
        startIdleAnimations()

        let overlayLayer = CAGradientLayer()
        overlayLayer.frame = wheelView.bounds
        overlayLayer.cornerRadius = wheelView.bounds.width / 2
        overlayLayer.colors = [
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.clear.cgColor,
            UIColor.yellow.withAlphaComponent(0.25).cgColor
        ]
        overlayLayer.locations = [0.0, 0.5, 1.0]
        overlayLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        overlayLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        wheelView.layer.addSublayer(overlayLayer)
    }

    private func addCenterHubWithText() {
        let hubRadius: CGFloat = wheelView.bounds.width * 0.13
        let hubDiameter = hubRadius * 2

        let hubContainer = CALayer()
        hubContainer.bounds = CGRect(x: 0, y: 0, width: hubDiameter, height: hubDiameter)
        hubContainer.position = CGPoint(x: wheelView.bounds.midX, y: wheelView.bounds.midY)

        let circleLayer = CAShapeLayer()
        circleLayer.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: hubDiameter, height: hubDiameter)).cgPath
        circleLayer.fillColor = UIColor.white.cgColor
        circleLayer.strokeColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0).cgColor
        circleLayer.lineWidth = 3

        let font = UIFont.systemFont(ofSize: 33, weight: .bold)
        let textLayer = CATextLayer()
        tapTextLayer = textLayer
        textLayer.string = "TAP"
        textLayer.font = CGFont(font.fontName as CFString)
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = UIColor.brown.cgColor
        textLayer.contentsScale = traitCollection.displayScale

        let textSize = ("TAP" as NSString).size(withAttributes: [.font: font])
        textLayer.frame = CGRect(x: (hubDiameter - textSize.width) / 2,
                                 y: (hubDiameter - textSize.height) / 2,
                                 width: textSize.width, height: textSize.height)

        hubContainer.addSublayer(circleLayer)
        hubContainer.addSublayer(textLayer)
        wheelView.layer.addSublayer(hubContainer)
    }

    private func drawPointer() {
        pointerLayer?.removeFromSuperlayer()

        let pointerWidth: CGFloat = 32
        let pointerHeight: CGFloat = 40

        let container = CALayer()
        container.name = "pointerLayer"

        let wheelFrame = wheelView.frame
        container.frame = CGRect(x: wheelFrame.maxX - 6,
                                 y: wheelFrame.midY - pointerHeight/2,
                                 width: pointerWidth + 16, height: pointerHeight)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: 16, y: pointerHeight/2))
        path.addLine(to: CGPoint(x: pointerWidth + 16, y: 0))
        path.addLine(to: CGPoint(x: pointerWidth + 16, y: pointerHeight))
        path.close()

        let triangle = CAShapeLayer()
        triangle.path = path.cgPath
        triangle.fillColor = UIColor.brown.cgColor
        triangle.shadowColor = UIColor.yellow.cgColor
        triangle.shadowOpacity = 0.4
        triangle.shadowOffset = CGSize(width: -2, height: 4)
        triangle.shadowRadius = 6

        let badgeSize: CGFloat = 14
        let badge = CAShapeLayer()
        badge.path = UIBezierPath(ovalIn: CGRect(x: 0, y: (pointerHeight - badgeSize)/2,
                                                 width: badgeSize, height: badgeSize)).cgPath
        badge.fillColor = UIColor.systemYellow.cgColor
        badge.shadowColor = UIColor.yellow.cgColor
        badge.shadowOpacity = 0.3
        badge.shadowOffset = CGSize(width: 0, height: 2)
        badge.shadowRadius = 4

        container.addSublayer(badge)
        container.addSublayer(triangle)

        view.layer.addSublayer(container)
        pointerLayer = container
    }

    // MARK: - Idle Animations
    private func startIdleAnimations() {
        guard !isSpinning else { return }

        let hoverAnim = CABasicAnimation(keyPath: "transform.scale")
        hoverAnim.fromValue = 1.0
        hoverAnim.toValue = 1.06
        hoverAnim.duration = 1.5
        hoverAnim.autoreverses = true
        hoverAnim.repeatCount = .infinity
        hoverAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        wheelView.layer.add(hoverAnim, forKey: "hoverAnimation")
        pointerLayer?.add(hoverAnim, forKey: "hoverAnimation")

        let opacityAnim = CABasicAnimation(keyPath: "shadowOpacity")
        opacityAnim.fromValue = 0.6
        opacityAnim.toValue = 0.3

        let radiusAnim = CABasicAnimation(keyPath: "shadowRadius")
        radiusAnim.fromValue = 18
        radiusAnim.toValue = 10

        let glowGroup = CAAnimationGroup()
        glowGroup.animations = [opacityAnim, radiusAnim]
        glowGroup.duration = 1.5
        glowGroup.autoreverses = true
        glowGroup.repeatCount = .infinity
        glowGroup.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rimLayer?.add(glowGroup, forKey: "glowAnimation")
    }

    private func stopIdleAnimations() {
        wheelView.layer.removeAnimation(forKey: "hoverAnimation")
        rimLayer?.removeAnimation(forKey: "glowAnimation")
        pointerLayer?.removeAnimation(forKey: "hoverAnimation")
        wheelView.transform = .identity
        pointerLayer?.transform = CATransform3DIdentity
    }

    // MARK: - Actions
    @IBAction func homeButtonTapped(_ sender: UIButton) {
        navigationController?.popToRootViewController(animated: true)
    }
    private func navigateToWordsCategories() {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let wordsVC = sb.instantiateViewController(withIdentifier: "WordsCategoriesViewController") as? WordsCategoriesViewController else { return }
        
        // Pass the custom images
        wordsVC.customImage3 = UIImage(named: "sound_detective")
        wordsVC.customImage4 = UIImage(named: "word_builder")
        wordsVC.customImage5 = UIImage(named: "quiz_my_story")
        wordsVC.customImage6 = UIImage(named: "rhyme_words")
        wordsVC.customPowerImage = UIImage(named: "fluency_drills")
        
        // Pass the injected dependency!
        wordsVC.writingGameplayManager = self.writingGameplayManager
        
        // 👇 NEW: Pass the mode flag and phonics dependencies
        wordsVC.isExercisesMode = true
        wordsVC.phonicsGameplayManager = self.phonicsGameplayManager
        wordsVC.bundleDataLoader = self.bundleDataLoader
        wordsVC.speechManager = self.speechManager
        wordsVC.speechRecognitionManager = self.speechRecognitionManager
        wordsVC.gameTimerManager = self.gameTimerManager
        
        navigationController?.pushViewController(wordsVC, animated: true)
    }
}
