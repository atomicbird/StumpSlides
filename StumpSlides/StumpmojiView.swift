//
//  StackmojiView.swift
//  StumpSlides
//
//  Created by Tom Harrington on 8/10/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import UIKit

class StumpmojiView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        isUserInteractionEnabled = false
    }
    
    static let messageColors: [UIColor] = [.red, .orange, .yellow, .green, .blue, .purple]

    static let allowedMessages = ["😀", "🔥", "🤩", "😍", "🎉", "✅", "❌", "🌈", "🌟", "❤️", "🍪", "🍔", "🌶", "♻️", "❤️", "💥", "🎈", "💩", "🤖", "🤮", "💯", "❓", "❗️", "🆗", "🍺", "🍷", "📱", "💡", "😱", "dogcow", "360iDev", "apple-logo"]
    
    func addMessage(_ message: String) -> Void {
        let messageInitialXPosition = CGFloat.random(in: 20...frame.maxX-20)
        
        let messageView: UIView = {
            if message == "dogcow" || message == "360iDev" || message == "apple-logo" {
                let image = UIImage(named: message)
                let imageView = UIImageView(image: image)
                imageView.frame = CGRect(x: messageInitialXPosition, y: 0, width: 100, height: 100)
                return imageView
            } else {
                let view = UILabel(frame: CGRect(x: messageInitialXPosition, y: 0, width: 100, height: 100))
                view.text = message
                view.font = UIFont.systemFont(ofSize: 60, weight: .heavy)
                view.sizeToFit()
                view.backgroundColor = .clear
                return view
            }
        }()
        addSubview(messageView)
        
        let messageFinalXPosition = CGFloat.random(in: 20...frame.maxX-20)
        let messageFinalYPosition = CGFloat.random(in: frame.maxY ... 1.25*frame.maxY)
        let animationTime = TimeInterval.random(in: 5...15)
        let animationRotation = CGFloat.random(in: -8*CGFloat.pi...8*CGFloat.pi)

        UIView.animate(withDuration: animationTime, animations: {
            messageView.frame.origin.y = messageFinalYPosition
            messageView.frame.origin.x = messageFinalXPosition
            messageView.alpha = 0
            messageView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5).concatenating(CGAffineTransform(rotationAngle: animationRotation))
        }) { (_) in
            messageView.removeFromSuperview()
        }
    }
    
    func addRandomMessages() -> Void {
        for _ in 1...100 {
//            addMessage(StumpmojiView.allowedMessages.randomElement()!)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int.random(in: 1...10000))) {
                self.addMessage(StumpmojiView.allowedMessages.randomElement()!)
            }
            
        }
    }
}
