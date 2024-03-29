//
//  ByteGameViewController.swift
//  ByteGameViewController
//
//  Created by Tom Harrington on 7/20/21.
//  Copyright © 2021 Atomic Bird LLC. All rights reserved.
//

import UIKit

class ByteGameViewController: UIViewController {
    @IBOutlet var attendeeButtonsRaw: [UIButton]! {
        didSet {
            // The outlet collection is unsorted, so sort it based on location. Set tags so we'll know which was tapped later on.
            attendeeButtons = attendeeButtonsRaw.sorted(by: { buttonA, buttonB in
                buttonA.frame.origin.x > buttonB.frame.origin.x
            })
            for (index, button) in attendeeButtons.enumerated() {
                button.tag = index
                button.addTarget(self, action: #selector(toggleAttendee), for: .touchUpInside)
            }
        }
    }
    var attendeeButtons: [UIButton] = []
    @IBOutlet var speakerButtonsRaw: [UIButton]! {
        didSet {
            // The outlet collection is unsorted, so sort it based on location. Set tags so we'll know which was tapped later on.
            speakerButtons = speakerButtonsRaw.sorted(by: { buttonA, buttonB in
                buttonA.frame.minX > buttonB.frame.minX
            })
            for (index, button) in speakerButtons.enumerated() {
                button.tag = index
                button.addTarget(self, action: #selector(toggleSpeaker(_:)), for: .touchUpInside)
            }
        }
    }
    var bitIndicatorLabels = [UILabel]() // Every "*" label below the bits
    @IBOutlet var attendeeBitIndicatorsRaw: [UILabel]! {
        didSet {
            let attendeeBitIndicators = attendeeBitIndicatorsRaw.sorted { labelA, labelB in
                labelA.frame.minX > labelB.frame.minX
            }
            for (index, label) in attendeeBitIndicators.enumerated() { label.tag = index }
            bitIndicatorLabels.append(contentsOf: attendeeBitIndicators)
        }
    }
    @IBOutlet var speakerBitIndicatorsRaw: [UILabel]! {
        didSet {
            let speakerBitIndicators = speakerBitIndicatorsRaw.sorted { labelA, labelB in
                labelA.frame.minX > labelB.frame.minX
            }
            for (index, label) in speakerBitIndicators.enumerated() { label.tag = index }
            bitIndicatorLabels.append(contentsOf: speakerBitIndicators)
        }
    }
    var speakerButtons: [UIButton] = []
    @IBOutlet weak var attendeeTotalLabel: UILabel!
    @IBOutlet weak var speakerTotalLabel: UILabel!
    @IBOutlet var bitsToTotalDistanceConstraints: [NSLayoutConstraint]!
    @IBOutlet var totalScoreWidthConstraints: [NSLayoutConstraint]!
    @IBOutlet var bitDigitWidthConstraints: [NSLayoutConstraint]!
    @IBOutlet var bitHorizontalSpacingConstraints: [NSLayoutConstraint]!
    @IBOutlet var scoreContainerViews: [UIView]!
    @IBOutlet weak var totalScoreStyleSwitch: UISegmentedControl!
    @IBOutlet weak var mainContainerView: UIView!
    @IBOutlet var byteHeaderLabels: [UILabel]!
    @IBOutlet weak var timerButton: UIButton!
    var totalScoreStyleHex = true
    
    var attendeeScore = 0
    var speakerScore = 0
    var activeBit = 0
    // Start at 8 seconds, double every time, max out at 255 (the max 8-bit unsigned value)
    let timeLimits: [Int] = [8, 16, 32, 64, 128, 255, 255, 255]
    var remainingTime: Int = 0
    var questionTimer: Timer?
    
    var timerExpired: (() -> Void)?
    
    let fontName = "Level Up"
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        modalPresentationStyle = .fullScreen
    }
    
    var pinchGestureRecognizer: UIPinchGestureRecognizer!
    var rotationGestureRecognizer: UIRotationGestureRecognizer!
    var dismissGestureRecognizer: UISwipeGestureRecognizer!
    
    var dismissHandler: ((ByteGameViewController) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        dismissGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(dismiss))
        dismissGestureRecognizer.direction = .down
        view.addGestureRecognizer(dismissGestureRecognizer)
        
        let swipeLeftGesture = UISwipeGestureRecognizer(target: self, action: #selector(changeActiveBit(_:)))
        swipeLeftGesture.direction = .left
        view.addGestureRecognizer(swipeLeftGesture)
        let swipeRightGesture = UISwipeGestureRecognizer(target: self, action: #selector(changeActiveBit(_:)))
        swipeRightGesture.direction = .right
        view.addGestureRecognizer(swipeRightGesture)
        
        bitsToTotalDistanceConstraints.forEach { $0.constant = 40 }  // A hack because I couldn't get layout right without it.

        pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        pinchGestureRecognizer.delegate = self
        view.addGestureRecognizer(pinchGestureRecognizer)
        rotationGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(handleRotationGesture(_:)))
        view.addGestureRecognizer(rotationGestureRecognizer)
        rotationGestureRecognizer.delegate = self
        
        remainingTime = timeLimits[activeBit]

        updateTotals()
        updateBitIndicators()
        updateRemainingTime()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }
    
    var calculatedFontsByWidth: [Int: UIFont] = [:]
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIView.animate(withDuration: 0.3) {
            self.view.alpha = 1.0
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        logMilestone()
        
        // Lots lots lots of manual constraint bashing because I couldn't get it to work right otherwise.
        // The goal is to have the button and label fonts as big as possible given the current width, and of course all the same size.
        // This leads to lots of messing about figuring out what that font size is, and constraining all the buttons and labels to the right sizes.
        // Button width constraints are also related to wanting to keep everything in a fixed position as values change. It's no good if changing bits from 0 to 1 makes the layout change because the intrinsic content size is different.
        let spaceAvailableForLabels = mainContainerView.frame.width
        - 2*20 // Leading/trailing distance
        - bitsToTotalDistanceConstraints[0].constant
        - 7*bitHorizontalSpacingConstraints[0].constant
        logMilestone("Available label space: (\(mainContainerView.frame.width), \(bitsToTotalDistanceConstraints[0].constant), \(bitHorizontalSpacingConstraints[0].constant)) \(spaceAvailableForLabels)")

        var scoreFont: UIFont
        // Test strings used for layout calculations
        let totalScoreTestText = "WWW"
        let bitButtonTestText = "0"
        
        if let targetFont = calculatedFontsByWidth[Int(spaceAvailableForLabels)] {
            scoreFont = targetFont
        } else {
            var fontSize: CGFloat = 0
            var spaceNeededForLabels: CGFloat = 0
            
            repeat {
                fontSize += 10
                let font = UIFont(name: fontName, size: fontSize)
                let attributes: [NSAttributedString.Key: Any] = [.font: font as Any]
                spaceNeededForLabels = 8*(bitButtonTestText as NSString).size(withAttributes: attributes).width + (totalScoreTestText as NSString).size(withAttributes: attributes).width
                logMilestone("Font size: \(fontSize) uses space \(spaceNeededForLabels)")
            } while spaceNeededForLabels < spaceAvailableForLabels
            fontSize -= 10
            // Force unwrap because I want this to crash during dev if the font isn't there.
            scoreFont = UIFont(name: fontName, size: fontSize)!
            calculatedFontsByWidth[Int(spaceAvailableForLabels)] = scoreFont
        }
        
        [attendeeButtons, speakerButtons].forEach { buttonArray in
            buttonArray.forEach { $0.titleLabel?.font = scoreFont }
        }
        // Set the width of each bit digit button
        bitDigitWidthConstraints.forEach {
            $0.constant = (bitButtonTestText as NSString).size(withAttributes: [.font: scoreFont as Any]).width
        }
        attendeeTotalLabel.font = scoreFont
        speakerTotalLabel.font = scoreFont
        // Set the width of the total score fields
        totalScoreWidthConstraints.forEach {
            // I don't know why the extra 20 is necessary. Without it, values > 200 end up as "2..".
            $0.constant = (totalScoreTestText as NSString).size(withAttributes: [.font: scoreFont as Any]).width + 20
        }
        
        totalScoreStyleSwitch.setTitleTextAttributes([.font: UIFont(name: fontName, size: scoreFont.pointSize/6.0) as Any, .foregroundColor: UIColor.green as Any], for: .normal)
        bitIndicatorLabels.forEach { $0.font = UIFont(name: fontName, size: scoreFont.pointSize/3.0) }
        byteHeaderLabels.forEach { $0.font = UIFont(name: fontName, size: scoreFont.pointSize * 0.75) }
        timerButton.titleLabel?.font = UIFont(name: fontName, size: scoreFont.pointSize * 0.5)
    }
    
    @IBAction func dismiss(_ sender: Any) {
        dismissHandler?(self)
    }

    @objc func changeActiveBit(_ sender: UISwipeGestureRecognizer) -> Void {
        // No changing the active bit unless the timer is stopped.
        guard questionTimer == nil else { return }
        if sender.direction == .left {
            activeBit = min(activeBit + 1, 7)
        } else {
            activeBit = max(activeBit - 1, 0)
        }
        remainingTime = timeLimits[activeBit]
        updateBitIndicators()
        updateRemainingTime()
    }
    
    @IBAction func toggleAttendee(_ sender: UIButton) {
        let toggledBitIndex = sender.tag
        guard toggledBitIndex == activeBit else { return }
        attendeeScore ^= 1 << toggledBitIndex
        let newBitValue = (attendeeScore >> toggledBitIndex) & 1
        sender.setTitle("\(newBitValue)", for: .normal)
        if newBitValue == 1 {
            speakerButtons[toggledBitIndex].setTitle("0", for: .normal)
            speakerScore &= ~(1 << toggledBitIndex)
        }
        print("Speaker score: \(speakerScore), attendee: \(attendeeScore)")
        updateTotals()
    }
    
    @IBAction func toggleSpeaker(_ sender: UIButton) {
        let toggledBitIndex = sender.tag
        guard toggledBitIndex == activeBit else { return }
        speakerScore ^= 1 << toggledBitIndex
        let newBitValue = (speakerScore >> toggledBitIndex) & 1
        sender.setTitle("\(newBitValue)", for: .normal)
        if newBitValue == 1 {
            attendeeButtons[toggledBitIndex].setTitle("0", for: .normal)
            attendeeScore &= ~(1 << toggledBitIndex)
        }
        print("Speaker score: \(speakerScore), attendee: \(attendeeScore)")
        updateTotals()
    }
    
    func updateTotals() {
        if totalScoreStyleHex {
            attendeeTotalLabel.text = "\(String(format:"%X", attendeeScore))"
            speakerTotalLabel.text = "\(String(format:"%X", speakerScore))"
        } else {
            attendeeTotalLabel.text = "\(attendeeScore)"
            speakerTotalLabel.text = "\(speakerScore)"
        }
    }
    
    func updateBitIndicators() -> Void {
        bitIndicatorLabels.forEach { $0.text = ($0.tag == activeBit) ? "*" : "" }
    }
    
    @IBAction func toggleScoreStyle(_ sender: Any) {
        totalScoreStyleHex.toggle()
        updateTotals()
    }
    
    /// Update remaining time label, formatted as binary
    func updateRemainingTime() -> Void {
        var timeString = String(remainingTime, radix: 2)
        while timeString.count < 8 { timeString = "0\(timeString)" }
        timerButton.setTitle("Time: \(timeString)", for: .normal)
    }
    
    func flashScreen() -> Void {
        var flashCount = 32
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            if flashCount.isMultiple(of: 2) {
                self?.view.backgroundColor = .red
                self?.view.layer.filters = [CIFilter(name: "CIColorInvert") as Any]
            } else {
                self?.view.backgroundColor = .black
                self?.view.layer.filters = []
            }
            flashCount -= 1
            if flashCount <= 0 {
                timer.invalidate()
            }
        }
    }
    
    @IBAction func toggleTimer(_ sender: Any) {
        if questionTimer == nil {
            questionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { _ in
                self.remainingTime = max(self.remainingTime - 1, 0)
                self.updateRemainingTime()
                if self.remainingTime <= 0 {
                    self.questionTimer?.invalidate()
                    self.questionTimer = nil
                    self.timerExpired?()
                    self.flashScreen()
                }
            })
        } else {
            questionTimer?.invalidate()
            questionTimer = nil
        }
    }
    
    var pinchStartSize = CGSize.zero
    
    enum PinchDirection {
        case inward
        case outward
        case unknown
    }
    var currentPinchDirection: PinchDirection?
    var startingTransform: CGAffineTransform?
    var pinchTransform: CGAffineTransform?
    var rotationTransform: CGAffineTransform?
    
    @objc func handlePinchGesture(_ pinchRecognizer: UIPinchGestureRecognizer) -> Void {
        switch pinchRecognizer.state {
        case .began:
            pinchStartSize = view.bounds.size
            logMilestone("Pinch start size: \(pinchStartSize)")
            currentPinchDirection = .unknown
            startingTransform = view.transform
        case .changed:
            logMilestone("Pinch scale: \(pinchRecognizer.scale), velocity: \(pinchRecognizer.velocity)")
            currentPinchDirection = pinchRecognizer.velocity > 0 ? .outward : .inward
            
            // Adjusting constraints on the fly gets complicated because even if the math is right, old constraints don't seem to get deactivated right away, so you end up with conflicting constraints from applying new ones while old ones haven't gone away yet.
            
            pinchTransform = CGAffineTransform(scaleX: pinchRecognizer.scale, y: pinchRecognizer.scale)
            updateTransforms()
        case .ended, .cancelled, .failed:
            UIView.animate(withDuration: 0.3) {
                if let superview = self.view.superview {
                    let newWidthConstraint: NSLayoutConstraint
                    let newHeightConstraint: NSLayoutConstraint
                    if self.currentPinchDirection == .outward {
                        newWidthConstraint = self.view.widthAnchor.constraint(equalTo: superview.widthAnchor)
                        newHeightConstraint = self.view.heightAnchor.constraint(equalTo: superview.heightAnchor)
                    } else {
                        newWidthConstraint = self.view.widthAnchor.constraint(equalTo: superview.widthAnchor, multiplier: 0.5)
                        newHeightConstraint = self.view.heightAnchor.constraint(equalTo: superview.heightAnchor, multiplier: 0.5)
                    }
                    NSLayoutConstraint.deactivate([self.viewWidthConstraint!, self.viewHeightConstraint!])
                    NSLayoutConstraint.activate([newWidthConstraint, newHeightConstraint])
                    self.viewWidthConstraint = newWidthConstraint
                    self.viewHeightConstraint = newHeightConstraint
                }
                self.view.transform = CGAffineTransform.identity
                self.pinchTransform = nil
                self.currentPinchDirection = nil
            }
        default:
            self.view.transform = CGAffineTransform.identity
            self.pinchTransform = nil
            currentPinchDirection = nil
        }
    }
    
    @objc func handleRotationGesture(_ rotationRecognizer: UIRotationGestureRecognizer) -> Void {
        logMilestone("Rotation: \(rotationRecognizer.rotation)")
        guard currentPinchDirection != nil else { return } // No rotation unless a pinch started
        switch rotationRecognizer.state {
        case .began:
            break
        case .changed:
            rotationTransform = CGAffineTransform(rotationAngle: rotationRecognizer.rotation)
            updateTransforms()
        case .ended, .cancelled, .failed:
            rotationTransform = nil
        default:
            rotationTransform = nil
        }
    }
    
    func updateTransforms() -> Void {
        guard var newTransform = startingTransform else { return }
        if let rotationTransform = rotationTransform {
            newTransform = newTransform.concatenating(rotationTransform)
        }
        if let pinchTransform = pinchTransform {
            newTransform = newTransform.concatenating(pinchTransform)
        }
        view.transform = newTransform
    }
    
    var viewWidthConstraint: NSLayoutConstraint?
    var viewHeightConstraint: NSLayoutConstraint?
    
    override func didMove(toParent parent: UIViewController?) {
        // constrain
        guard let superview = view.superview else { return }
        
        viewWidthConstraint = view.widthAnchor.constraint(equalTo: superview.widthAnchor, multiplier: 1.0)
        viewHeightConstraint = view.heightAnchor.constraint(equalTo: superview.heightAnchor, multiplier: 1.0)
        
        NSLayoutConstraint.activate([
            superview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            viewWidthConstraint!,
            viewHeightConstraint!,
            superview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        super.didMove(toParent: parent)
    }
}

extension ByteGameViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Pinch and rotate are simultaneous with each other but dismiss stands alone.
        return (gestureRecognizer == pinchGestureRecognizer && otherGestureRecognizer == rotationGestureRecognizer) ||
        (gestureRecognizer == rotationGestureRecognizer && otherGestureRecognizer == pinchGestureRecognizer)
    }
}
