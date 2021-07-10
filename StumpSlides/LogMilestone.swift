//
//  LogMilestone.swift
//  StumpSlides
//
//  Created by Tom Harrington on 10/21/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import Foundation

/// Log the current filename and function, with an optional extra message. Call this with no arguments to simply print the current file and function. Log messages will include an Emoji selected from a list in the function, based on the hash of the filename, to make it easier to see which file a message comes from.
/// - Parameter message: Optional message to include
/// - Parameter file: Defaults to the filename where this function is called.
/// - Parameter function: Defaults to the function name where this function is called.
func logMilestone(_ message: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
    // Feel free to change the list of Emojis, but don't make it shorter, because a longer list is better.
    let logEmojis = ["😀","😎","😱","😈","👺","👽","👾","🤖","🎃","👍","👁","🧠","🎒","🧤","🐶","🐱","🐭","🐹","🦊","🐻","🐨","🐵","🦄","🦋","🌈","🔥","💥","⭐️","🍉","🥝","🌽","🍔","🍿","🎁","❤️","🧡","💛","💚","💙","💜","🔔"]
    let logEmoji = logEmojis[abs(file.hash % logEmojis.count)]
    if let message = message {
        print("Milestone: \(logEmoji) \((file as NSString).lastPathComponent):\(line) \(function): \(message)")
    } else {
        print("Milestone: \(logEmoji) \((file as NSString).lastPathComponent):\(line) \(function)")
    }
}
