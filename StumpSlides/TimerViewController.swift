//
//  TimerViewController.swift
//  TimerViewController
//
//  Created by Tom Harrington on 8/14/21.
//  Copyright © 2021 Atomic Bird LLC. All rights reserved.
//

import UIKit

class TimerViewController: UIViewController {

    struct InitialTimes: ExpressibleByArrayLiteral, Sequence, IteratorProtocol {
        mutating func next() -> Int? {
            defer {
                index = (index + 1) % initialTimes.count
            }
            return initialTimes[index]
        }
        
        mutating func nextInitialTime() -> Int {
            return next() ?? 60
        }
        
        var current: Int {
            return initialTimes[index]
        }
        
        var initialTimes: [Int]
        var index = 0
        
        init(arrayLiteral elements: Int...) {
            initialTimes = elements
        }
    }

    enum TimeFormat {
        case minutesAndSeconds
        case binarySeconds
    }
    
    var initialTimes: InitialTimes = [10]
    
    fileprivate var remainingTime: Int = 0 {
        didSet {
            updateRemainingTime()
        }
    }
    var questionTimer: Timer?
    var timeFormat = TimeFormat.minutesAndSeconds
    
    /// Set this to change the default timer flashing when time runs out
    var timerExpired: (() -> Void)?

    var fontName = "Level Up"
    var fontSize = 50.0

    @IBOutlet weak var timerButton: UIButton!
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        timerButton.titleLabel?.font = UIFont(name: fontName, size: fontSize)
        timerButton.titleLabel?.adjustsFontSizeToFitWidth = true
        timerButton.titleLabel?.minimumScaleFactor = 0.1
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTap))
        doubleTap.numberOfTapsRequired = 2
        timerButton.addGestureRecognizer(doubleTap)
        
        updateRemainingTime()
        remainingTime = initialTimes.current
    }
    
    @objc func doubleTap() -> Void {
        print("Double tap")
        questionTimer?.invalidate()
        questionTimer = nil
        if remainingTime == 0 {
            remainingTime = initialTimes.current
        } else {
            remainingTime = initialTimes.nextInitialTime()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateRemainingTime()
    }
    
    lazy var questionTimeFormatter: DateComponentsFormatter = {
        let dateCompsFormatter = DateComponentsFormatter()
        dateCompsFormatter.allowedUnits = [.minute, .second]
        dateCompsFormatter.zeroFormattingBehavior = .pad
        dateCompsFormatter.unitsStyle = .positional
        return dateCompsFormatter
    }()

    func updateRemainingTime() -> Void {
        print("Updating remaining time: \(remainingTime)")
        switch timeFormat {
        case .minutesAndSeconds:
            let timeString = questionTimeFormatter.string(from:TimeInterval(remainingTime))
            timerButton?.setTitle(timeString ?? "ERROR!", for: .normal)
        case .binarySeconds:
            var timeString = String(remainingTime, radix: 2)
            while timeString.count < 8 { timeString = "0\(timeString)" }
            timerButton?.setTitle("Time: \(timeString)", for: .normal)
        }
    }

    @IBAction func toggleTimer(_ sender: Any) {
        if questionTimer == nil {
            questionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { _ in
                self.remainingTime = max(self.remainingTime - 1, 0)
                if self.remainingTime <= 0 {
                    self.questionTimer?.invalidate()
                    self.questionTimer = nil
                    // Call timerExpired, if set, otherwise flash the timer UI
                    (self.timerExpired ?? self.flashTimer)()
                }
            })
        } else {
            questionTimer?.invalidate()
            questionTimer = nil
        }
    }

    func flashTimer() -> Void {
        var flashCount = 32
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            if flashCount.isMultiple(of: 2) {
                self?.view.backgroundColor = .white
                self?.view.layer.filters = [CIFilter(name: "CIColorInvert") as Any]
            } else {
                self?.view.backgroundColor = .green
                self?.view.layer.filters = []
            }
            flashCount -= 1
            if flashCount <= 0 {
                self?.view.backgroundColor = .clear
                self?.view.layer.filters = []
                timer.invalidate()
            }
        }
    }
}
