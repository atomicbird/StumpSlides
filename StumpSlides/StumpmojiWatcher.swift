//
//  StumpmojiWatcher.swift
//  StumpSlides
//
//  Created by Tom Harrington on 8/10/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import Foundation
import Firebase

struct StumpScores: Equatable {
    enum ScoreKeys: String, CaseIterable {
        case panelScore
        case audienceScore
        case panelAskedCount
        case audienceAskedCount
    }
    
    typealias StumpScoresDict = [ScoreKeys:Int]
    typealias SnapshotDict = [String:Int]
    
    var scoreDict: StumpScoresDict
    
    /// Initialize all zeroe scores
    init() {
        scoreDict = StumpScoresDict()
        ScoreKeys.allCases.forEach { scoreDict[$0] = 0 }
    }

    /// Initialize from a Firebase snapshot
    init(stringDict: SnapshotDict) {
        scoreDict = StumpScoresDict()
        ScoreKeys.allCases.forEach {
            scoreDict[$0] = stringDict[$0.rawValue] ?? 0
        }
    }

    /// Convert to plist types for Firebase
    func stringDict() -> [String:Int] {
        var stringDict: [String:Int] = [:]
        scoreDict.forEach { stringDict[$0.key.rawValue] = $0.value }
        return stringDict
    }
    
    /// Wrap dictionary access with a subscript
    subscript(key: ScoreKeys) -> Int {
        get {
            return scoreDict[key] ?? 0
        }
        set {
            scoreDict[key] = newValue
        }
    }
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
        guard let scoreStringDict = snapshot.value as? StumpScores.SnapshotDict else { return }
        let score = StumpScores(stringDict: scoreStringDict)
        guard score != self.score else { return }
        self.score = score
        print("New score value: \(score)")
    }
}
