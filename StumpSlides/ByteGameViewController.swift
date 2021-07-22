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
    var speakerButtons: [UIButton] = []
    @IBOutlet weak var attendeeTotalLabel: UILabel!
    @IBOutlet weak var speakerTotalLabel: UILabel!
    @IBOutlet var bitsToTotalDistanceConstraints: [NSLayoutConstraint]!
    @IBOutlet var totalScoreWidthConstraints: [NSLayoutConstraint]!
    @IBOutlet var bitDigitWidthConstraints: [NSLayoutConstraint]!
    @IBOutlet var bitHorizontalSpacingConstraints: [NSLayoutConstraint]!
    @IBOutlet var scoreContainerViews: [UIView]!
    @IBOutlet weak var totalScoreStyleSwitch: UISegmentedControl! {
        didSet {
            totalScoreStyleSwitch.setTitleTextAttributes([.font: UIFont(name: fontName, size: 20) as Any, .foregroundColor: UIColor.green as Any], for: .normal)
        }
    }
    var totalScoreStyleHex = true
    
    var attendeeScore = 0
    var speakerScore = 0
    
    let fontName = "Level Up"
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        modalPresentationStyle = .fullScreen
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let dismissGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(dismiss))
        dismissGestureRecognizer.direction = .down
        view.addGestureRecognizer(dismissGestureRecognizer)
        
        bitsToTotalDistanceConstraints.forEach { $0.constant = 40 }  // A hack because I couldn't get layout right without it.

        updateTotals()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }
    
    var calculatedFontsByWidth: [Int: UIFont] = [:]
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        logMilestone()
        
        // Lots lots lots of manual constraint bashing because I couldn't get it to work right otherwise.
        // The goal is to have the button and label fonts as big as possible given the current width, and of course all the same size.
        // This leads to lots of messing about figuring out what that font size is, and constraining all the buttons and labels to the right sizes.
        // Button width constraints are also related to wanting to keep everything in a fixed position as values change. It's no good if changing bits from 0 to 1 makes the layout change because the intrinsic content size is different.
        let spaceAvailableForLabels = scoreContainerViews[0].frame.width
        - 2*20 // Leading/trailing distance
        - bitsToTotalDistanceConstraints[0].constant
        - 7*bitHorizontalSpacingConstraints[0].constant
        logMilestone("Available label space: (\(scoreContainerViews[0].frame.width), \(bitsToTotalDistanceConstraints[0].constant), \(bitHorizontalSpacingConstraints[0].constant)) \(spaceAvailableForLabels)")

        var scoreFont: UIFont
        // Test strings used for layout calculations
        let totalScoreTestText = "255"
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
    }
    
    @IBAction func dismiss(_ sender: Any) {
        dismiss(animated: true)
    }

    @IBAction func toggleAttendee(_ sender: UIButton) {
        let toggledBitIndex = sender.tag
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
    @IBAction func toggleValue(_ sender: UIButton) {
        let toggledBit = sender.tag
        speakerButtons[toggledBit].setTitle("0", for: .normal)
        attendeeButtons[toggledBit].setTitle("0", for: .normal)
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
    
    @IBAction func toggleScoreStyle(_ sender: Any) {
        totalScoreStyleHex.toggle()
        updateTotals()
    }
}
