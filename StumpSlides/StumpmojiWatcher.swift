//
//  StumpmojiWatcher.swift
//  StumpSlides
//
//  Created by Tom Harrington on 8/10/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import Foundation
import Firebase

class StumpmojiWatcher {
    var postListRef: DatabaseReference!
    var ref: DatabaseReference!
    var startDate = Date()
    
    var stumpmojiReceived: ((String) -> Void)?

    func startWatching() -> Void {
        // Use Firebase library to configure APIs
        FirebaseApp.configure()
        
        ref = Database.database().reference()
        
        postListRef = ref.child("/stumps/")
        
        postListRef.observe(.childAdded) { (snapshot) in
//            print("Snapshot: \(snapshot)")
            guard let stumpEntry = snapshot.value as? [String:Any] else { return }
            guard let messageTimestampMs = stumpEntry["messageDate"] as? Double else { return }
            guard (messageTimestampMs/1000 > self.startDate.timeIntervalSince1970) else { return }
            guard let message = stumpEntry["message"] as? String else { return }
            print("Received: \(message)")
            self.stumpmojiReceived?(message)
        }
    }
}
