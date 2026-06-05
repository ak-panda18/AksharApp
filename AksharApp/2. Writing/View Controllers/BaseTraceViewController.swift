import UIKit
import PencilKit
import AVFoundation

class BaseTraceViewController: UIViewController {

    // MARK: - Configuration Properties
    var contentType: WritingContentType = .letters
    var currentIndex: Int = 0
    var categoryKey: String { contentType == .letters ? "letters" : "numbers" }
    var activeAnimationLayers: [CAShapeLayer] = []
    var currentAnimationID = 0
    var brushWidth: CGFloat = 45.0

    // MARK: - Injected
    var writingGameplayManager: WritingGameplayManager!
    var coverageThreshold: CGFloat = 0.30
    var lastValidatedPoint: CGPoint = .zero
    var tracingHandLayer: CALayer?
    
    // Guided Learning Path
    weak var sessionDelegate: AnyObject?
    var orchestrator: SessionOrchestrator?

    
    // MARK: - State
    var isTracingLocked = false
    let synthesizer = AVSpeechSynthesizer()
    
    // MARK: - Pane Data Collections
    var paneLetterImageViews: [UIImageView] = []
    var paneCommittedCanvases: [PKCanvasView] = []
    
    var paneShapeLayers: [CAShapeLayer] = []
    var panePaths: [UIBezierPath] = []
    
    var paneStrokeSegments: [[[CGPoint]]] = []
    
    var paneCurrentStrokePoints: [[CGPoint]] = []
    var paneTransientTouchedPixels: [Set<Int>] = []
    var paneCurrentMaskIndex: [Int] = []
    var paneIsCompleted: [Bool] = []
    
    var paneMaskData: [[[UInt8]]] = []
    var paneMaskSizes: [[CGSize]] = []
    var paneMaskOpaqueCounts: [[Int]] = []
    var paneMaskAssetNames: [String] = []
    var traceStage: String { return "one" }

    var activePaneIndex: Int? = nil
    
    var themeBrown: CGColor {
        UIColor(red: 135/255, green: 87/255, blue: 55/255, alpha: 1).cgColor
    }

    var themeYellow: CGColor {
        UIColor(red: 248/255, green: 236/255, blue: 180/255, alpha: 1).cgColor
    }

    private func verifyDependencies() {
        assert(writingGameplayManager != nil, "writingGameplayManager was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
    }

    // MARK: - Setup Helpers
    func initPaneArrays(count: Int) {
        paneShapeLayers = []
        panePaths = []
        paneCurrentStrokePoints = Array(repeating: [], count: count)
        paneStrokeSegments = Array(repeating: [], count: count)
        paneTransientTouchedPixels = Array(repeating: Set<Int>(), count: count)
        paneCurrentMaskIndex = Array(repeating: 0, count: count)
        paneIsCompleted = Array(repeating: false, count: count)
        
        paneMaskData = Array(repeating: [], count: count)
        paneMaskSizes = Array(repeating: [], count: count)
        paneMaskOpaqueCounts = Array(repeating: [], count: count)
    }

    func setupShapeLayer(for view: UIImageView) {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.white.cgColor
        layer.lineWidth = self.brushWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.fillColor = UIColor.clear.cgColor
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        paneShapeLayers.append(layer)
        panePaths.append(UIBezierPath())
    }
    
    func setupCanvas(in wrapperView: UIView) -> PKCanvasView {
        let canvas = PKCanvasView(frame: .zero)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: UIColor.systemGreen, width: brushWidth)
        canvas.isUserInteractionEnabled = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        wrapperView.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: wrapperView.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor)
        ])
        return canvas
    }

    // MARK: - Mask Loading Logic
    func loadMasks(forPane paneIndex: Int, assetNames: [String]) {
        guard paneIndex < paneMaskData.count else { return }
        self.paneMaskData[paneIndex].removeAll()
        
        DispatchQueue.global(qos: .userInitiated).async {
            var tempMaskData: [[UInt8]] = []
            var tempSizes: [CGSize] = []
            var tempCounts: [Int] = []
            
            for name in assetNames {
                if let image = UIImage(named: name),
                   let (bytes, size) = TraceValidator.getNormalizedRGBAData(from: image) {
                    tempMaskData.append(bytes)
                    tempSizes.append(size)
                    
                    var count = 0
                    for k in stride(from: 3, to: bytes.count, by: 4) {
                        if bytes[k] > TraceValidator.alphaThreshold { count += 1 }
                    }
                    tempCounts.append(count)
                }
            }
            
            DispatchQueue.main.async {
                self.paneMaskData[paneIndex] = tempMaskData
                self.paneMaskSizes[paneIndex] = tempSizes
                self.paneMaskOpaqueCounts[paneIndex] = tempCounts
            }
        }
    }

    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isTracingLocked { return }
        guard let touch = touches.first else { return }
        
        activePaneIndex = nil
        
        for (i, imageView) in paneLetterImageViews.enumerated() {
            if paneIsCompleted[i] { continue }
            
            let loc = touch.location(in: imageView)
            if imageView.bounds.contains(loc) {
                activePaneIndex = i
                panePaths[i].move(to: loc)
                paneCurrentStrokePoints[i] = [loc]
                
                validatePoint(loc, paneIndex: i)
                break
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isTracingLocked { return }
        guard let idx = activePaneIndex, let touch = touches.first, let event = event else { return }
        
        let loc = touch.location(in: paneLetterImageViews[idx])
        
        let distance = hypot(loc.x - lastValidatedPoint.x, loc.y - lastValidatedPoint.y)
        if distance < 5.0 { return }
        
        if let coalesced = event.coalescedTouches(for: touch) {
            for cTouch in coalesced {
                let cLoc = cTouch.location(in: paneLetterImageViews[idx])
                panePaths[idx].addLine(to: loc)
                paneCurrentStrokePoints[idx].append(cLoc)
            }
        }
        
        validatePoint(loc, paneIndex: idx)
        lastValidatedPoint = loc
        paneShapeLayers[idx].path = panePaths[idx].cgPath
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let idx = activePaneIndex {
            if !paneCurrentStrokePoints[idx].isEmpty {
                paneStrokeSegments[idx].append(paneCurrentStrokePoints[idx])
            }
            paneCurrentStrokePoints[idx].removeAll()
        }
        activePaneIndex = nil
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let idx = activePaneIndex {
            resetTransientLayer(paneIndex: idx)
        }
        activePaneIndex = nil
    }

    // MARK: - Validation
    func validatePoint(_ point: CGPoint, paneIndex: Int) {
        let strokeIdx = paneCurrentMaskIndex[paneIndex]
        guard strokeIdx < paneMaskSizes[paneIndex].count else { return }
        
        let maskData = paneMaskData[paneIndex][strokeIdx]
        let maskSize = paneMaskSizes[paneIndex][strokeIdx]
        let imageView = paneLetterImageViews[paneIndex]
        
        if TraceValidator.isPointValid(point: point, inImageView: imageView, maskData: maskData, maskSize: maskSize) {
            paneShapeLayers[paneIndex].strokeColor = UIColor.white.cgColor
            
            let pixels = TraceValidator.getTouchedPixels(point: point, inImageView: imageView, maskSize: maskSize, brushWidth: brushWidth)
            for p in pixels {
                paneTransientTouchedPixels[paneIndex].insert(p)
            }
        } else {
            triggerDeviation(paneIndex: paneIndex)
        }
    }
    
    func triggerDeviation(paneIndex: Int) {
        if isTracingLocked { return }
        
        writingGameplayManager.trackMistake(index: currentIndex, category: categoryKey)
        
        isTracingLocked = true
        paneShapeLayers[paneIndex].strokeColor = UIColor.red.cgColor
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.resetTransientLayer(paneIndex: paneIndex)
            self.isTracingLocked = false
        }
    }
    
    // MARK: - Reset Helpers
    func resetTransientLayer(paneIndex: Int) {
        panePaths[paneIndex].removeAllPoints()
        paneShapeLayers[paneIndex].path = nil
        paneShapeLayers[paneIndex].strokeColor = UIColor.white.cgColor
        paneCurrentStrokePoints[paneIndex].removeAll()
        paneStrokeSegments[paneIndex].removeAll()
        paneTransientTouchedPixels[paneIndex].removeAll()
    }
    
    func resetPaneCompletely(_ index: Int) {
        resetTransientLayer(paneIndex: index)
        paneCommittedCanvases[index].drawing = PKDrawing()
        paneIsCompleted[index] = false
        paneCurrentMaskIndex[index] = 0
    }
    
    // MARK: - Green Ink Commit Logic
    func checkAndCommitGreenInk(paneIndex: Int) -> Bool {
        let strokeIdx = paneCurrentMaskIndex[paneIndex]
        guard strokeIdx < paneMaskOpaqueCounts[paneIndex].count else { return false }
        
        if !paneCurrentStrokePoints[paneIndex].isEmpty {
            paneStrokeSegments[paneIndex].append(paneCurrentStrokePoints[paneIndex])
            paneCurrentStrokePoints[paneIndex].removeAll()
        }
        
        let totalPixels = paneMaskOpaqueCounts[paneIndex][strokeIdx]
        if totalPixels == 0 {
            paneCurrentMaskIndex[paneIndex] += 1
            return true
        }
        
        let ratio = CGFloat(paneTransientTouchedPixels[paneIndex].count) / CGFloat(totalPixels)
        if ratio >= coverageThreshold {
            addGreenStrokeToCanvas(paneIndex: paneIndex)
            paneCurrentMaskIndex[paneIndex] += 1
            resetTransientLayer(paneIndex: paneIndex)
            if paneCurrentMaskIndex[paneIndex] >= paneMaskData[paneIndex].count {
                paneIsCompleted[paneIndex] = true
            }
            return true
        }
        return false
    }
    
    func addGreenStrokeToCanvas(paneIndex: Int) {
        let canvas = paneCommittedCanvases[paneIndex]
        var newStrokes = canvas.drawing.strokes
        
        let correctionFactor: CGFloat = 0.62
    
        var ink: PKInk
        
        if #available(iOS 17.0, *) {
            ink = PKInk(.monoline, color: .systemGreen)
        } else {
            ink = PKInk(.pen, color: .systemGreen)
        }
        
        let adjustedWidth = brushWidth * correctionFactor
        let strokeSize = CGSize(width: adjustedWidth, height: adjustedWidth)
        
        for segment in paneStrokeSegments[paneIndex] {
            guard segment.count > 1 else { continue }
            
            var pkPoints: [PKStrokePoint] = []
            var time: TimeInterval = 0
            
            for pt in segment {
                let pkPoint = PKStrokePoint(
                    location: pt,
                    timeOffset: time,
                    size: strokeSize,
                    opacity: 1.0,
                    force: 1.0,
                    azimuth: 0,
                    altitude: .pi/2
                )
                pkPoints.append(pkPoint)
                time += 0.002
            }
            
            let newPath = PKStrokePath(controlPoints: pkPoints, creationDate: Date())
            let newStroke = PKStroke(ink: ink, path: newPath)
            newStrokes.append(newStroke)
        }
        
        canvas.drawing = PKDrawing(strokes: newStrokes)
    }
    
    // MARK: - Style Helpers
    func applyBorderStyle(
        to view: UIView,
        borderColor: CGColor,
        borderWidth: CGFloat = 3,
        cornerRadius: CGFloat? = nil
    ) {
        view.layer.borderColor = borderColor
        view.layer.borderWidth = borderWidth
        
        if let r = cornerRadius {
            view.layer.cornerRadius = r
            view.clipsToBounds = true
        }
    }
}
extension BaseTraceViewController {
    func playTraceAnimation(at index: Int, for character: String) {
            guard index < paneLetterImageViews.count,
                  let letterData = TracingDataStore.getPath(for: character) else {
                return
            }
            
            let imageView = paneLetterImageViews[index]
            
            imageView.superview?.layoutIfNeeded()
            
            stopTraceAnimation()
            let contentRect = imageView.contentClippingRect
            
            guard let superview = imageView.superview else { return }
            let drawRect = imageView.convert(contentRect, to: superview)
            
                    if tracingHandLayer == nil {
                        let layer = CALayer()
                        if let image = UIImage(named: "handWithPencil")?.cgImage {
                            layer.contents = image
                        }
                        layer.bounds = CGRect(x: 0, y: 0, width: 400, height: 250)
                        
                        layer.anchorPoint = CGPoint(x: 0.2, y: 0.8)
                        layer.zPosition = 100
                        tracingHandLayer = layer
                    }
                    
                    if let hand = tracingHandLayer {
                        superview.layer.addSublayer(hand)
                        hand.opacity = 0
                    }
            
            currentAnimationID += 1
            let sessionID = currentAnimationID
            let traceColor = UIColor(red: 255/255, green: 231/255, blue: 136/255, alpha: 1.0)
            
            for stroke in letterData.strokes {
                let path = UIBezierPath()
                let start = mapPoint(stroke.start, rect: drawRect)
                let end = mapPoint(stroke.end, rect: drawRect)
                
                path.move(to: start)
                
                if let cp1 = stroke.control1 {
                    let cp1Mapped = mapPoint(cp1, rect: drawRect)
                    if let cp2 = stroke.control2 {
                        let cp2Mapped = mapPoint(cp2, rect: drawRect)
                        path.addCurve(to: end, controlPoint1: cp1Mapped, controlPoint2: cp2Mapped)
                    } else {
                        path.addQuadCurve(to: end, controlPoint: cp1Mapped)
                    }
                } else {
                    path.addLine(to: end)
                }
                
                let layer = CAShapeLayer()
                layer.path = path.cgPath
                layer.fillColor = UIColor.clear.cgColor
                layer.strokeColor = traceColor.cgColor
                
                layer.lineWidth = drawRect.width * 0.08
                layer.lineCap = .round
                layer.strokeEnd = 0
                layer.opacity = 0
                
                layer.shadowColor = traceColor.cgColor
                layer.shadowRadius = 8
                layer.shadowOpacity = 0.8
                layer.shadowOffset = .zero
                
                superview.layer.insertSublayer(layer, above: imageView.layer)
                activeAnimationLayers.append(layer)
            }
            
            animateLayerRecursive(index: 0, sessionID: sessionID)
        }
    
    private func mapPoint(_ point: CGPoint, rect: CGRect) -> CGPoint {
        return CGPoint(
            x: rect.origin.x + (point.x * rect.width),
            y: rect.origin.y + (point.y * rect.height)
        )
    }
    
    private func animateLayerRecursive(index: Int, sessionID: Int) {
           guard sessionID == currentAnimationID else { return }
           
           if index >= activeAnimationLayers.count {
               DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                   guard self?.currentAnimationID == sessionID else { return }
                   self?.performFadeOut()
               }
               return
           }
           
           let layer = activeAnimationLayers[index]
           layer.opacity = 1
           
           let strokeAnim = CABasicAnimation(keyPath: "strokeEnd")
           strokeAnim.fromValue = 0
           strokeAnim.toValue = 1
           strokeAnim.duration = 1.0
           strokeAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
           strokeAnim.fillMode = .forwards
           strokeAnim.isRemovedOnCompletion = false
           
           if let hand = tracingHandLayer, let path = layer.path {
               hand.opacity = 1.0
               
               let positionAnim = CAKeyframeAnimation(keyPath: "position")
               positionAnim.path = path
               positionAnim.duration = 1.0
               positionAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
               positionAnim.fillMode = .forwards
               positionAnim.isRemovedOnCompletion = false
               
               hand.add(positionAnim, forKey: "handMove")
           }
           
           CATransaction.begin()
           CATransaction.setCompletionBlock { [weak self] in
               self?.animateLayerRecursive(index: index + 1, sessionID: sessionID)
           }
           
           layer.add(strokeAnim, forKey: "strokeAnim")
           CATransaction.commit()
           
       }
    
    func stopTraceAnimation() {
        activeAnimationLayers.forEach { $0.removeFromSuperlayer() }
        activeAnimationLayers.removeAll()
        
        tracingHandLayer?.removeAllAnimations()
        tracingHandLayer?.removeFromSuperlayer()
        tracingHandLayer = nil
    }
    
    private func performFadeOut() {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.stopTraceAnimation()
        }
        
        for layer in activeAnimationLayers {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.duration = 0.5
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            layer.add(fade, forKey: "fadeAnim")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 0.0
            CATransaction.commit()
        }
        
        if let hand = tracingHandLayer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.duration = 0.5
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            hand.add(fade, forKey: "handFade")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hand.opacity = 0.0
            CATransaction.commit()
        }
        
        CATransaction.commit()
    }
    
    // MARK: - Shared Animation Logic
    func startTraceAnimationForPane0(force: Bool = false) {
        if !force {
            if paneIsCompleted.indices.contains(0) && paneIsCompleted[0] { return }
            
            let unlocked = writingGameplayManager.getHighestUnlockedIndex(category: categoryKey)
            if currentIndex < unlocked { return }
            
            if let drawing = writingGameplayManager.loadDrawing(index: currentIndex, category: categoryKey, stage: traceStage, part: traceStage == "one" ? "main" : "top"),
               !drawing.strokes.isEmpty {
                return
            }
        }
        
        let letterChar: String
        if contentType == .letters {
            let baseIndex = currentIndex / 2
            let isLower = (currentIndex % 2 != 0)
            let start = isLower ? 97 : 65
            letterChar = String(UnicodeScalar(start + baseIndex)!)
        } else {
            letterChar = "\(currentIndex)"
        }
        
        playTraceAnimation(at: 0, for: letterChar)
    }
}
