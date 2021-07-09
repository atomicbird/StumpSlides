//
//  StumpmojiWatcher.swift
//  StumpSlides
//
//  Created by Tom Harrington on 8/10/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import Foundation
import Firebase

struct StumpScores: Codable, Equatable {
    var panelScore = 0
    var audienceScore = 0
    var panelAskedCount = 0
    var audienceAskedCount = 0
}

class StumpmojiWatcher {
    var postListRef: DatabaseReference!
    var ref: DatabaseReference!
    var startDate = Date()

    var score = StumpScores() {
        didSet {
            print("New score: \(score)")
            self.scoreReceived?(score)
        }
    }

    var scoreRef: DatabaseReference!
    let scoresPath = "stumpScores"

    var stumpmojiReceived: ((String) -> Void)?
    var scoreReceived: ((StumpScores) -> Void)?

    func startWatching() -> Void {
        // Use Firebase library to configure APIs
        FirebaseApp.configure()
        
        ref = Database.database().reference()
        
        postListRef = ref.child("/stumps/")
        scoreRef = ref.child("/\(scoresPath)/")

        postListRef.observe(.childAdded) { (snapshot) in
//            print("Snapshot: \(snapshot)")
            guard let stumpEntry = snapshot.value as? [String:Any] else { return }
            guard let messageTimestampMs = stumpEntry["messageDate"] as? Double else { return }
            guard (messageTimestampMs/1000 > self.startDate.timeIntervalSince1970) else { return }
            guard let message = stumpEntry["message"] as? String else { return }
            logMilestone("Received: \(message)")
            self.stumpmojiReceived?(message)
        }
        // Load initial score value at launch
        scoreRef.observeSingleEvent(of: .value) { (snapshot) in
            logMilestone("Single snapshot: \(snapshot)")
            self.update(from: snapshot)
        }
        
        // Get new score values as they occur
        scoreRef.observe(.value) { (snapshot) in
            logMilestone("Value snapshot: \(snapshot)")
            self.update(from: snapshot)
        }
    }

    func update(from snapshot: DataSnapshot) -> Void {
        guard let scoreString = snapshot.value as? String else { return }
        guard let scoreData = scoreString.data(using: .utf8) else { return }
        guard let score = try? JSONDecoder().decode(StumpScores.self, from: scoreData) else { return }
        guard score != self.score else { return }
        self.score = score
        logMilestone("New score value: \(score)")
    }
}
