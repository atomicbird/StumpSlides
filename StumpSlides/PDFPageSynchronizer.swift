//
//  PDFPageSynchronizer.swift
//  StumpSlides
//
//  Created by Tom Harrington on 10/18/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import Foundation
import MultipeerConnectivity

protocol PDFPageSynchronizerDelegate {
    func pdfPageSynchronizer(_: PDFPageSynchronizer, didReceivePage: Int)
}

class PDFPageSynchronizer: NSObject {
    var peerID: MCPeerID!
    var mcSession: MCSession!
    var mcAdvertiserAssistant: MCAdvertiserAssistant!
    var testDataTimer: Timer!
    var mcBrowser: MCBrowserViewController!
    
    weak var presentingViewController: (UIViewController & PDFPageSynchronizerDelegate)?
    
    init(with viewController: UIViewController & PDFPageSynchronizerDelegate) {
        presentingViewController = viewController
        super.init()
        
        peerID = MCPeerID(displayName: UIDevice.current.name)
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self
    }

    func startSyncing() -> Void {
        guard mcAdvertiserAssistant == nil else { return }
        startHostingMP()
        joinSessionMP()
    }
    
    fileprivate func startHostingMP() {
        mcAdvertiserAssistant = MCAdvertiserAssistant(serviceType: "hws-kb", discoveryInfo: nil, session: mcSession)
        mcAdvertiserAssistant.start()
    }

    fileprivate func joinSessionMP() {
        mcBrowser = MCBrowserViewController(serviceType: "hws-kb", session: mcSession)
        mcBrowser.delegate = self
        presentingViewController?.present(mcBrowser, animated: true)
    }
    
    func send(pageNumber: Int) -> Void {
        if !self.mcSession.connectedPeers.isEmpty {
            var page = Int32(pageNumber)
            let pageNumberData = Data(bytes: &page, count: 4)
            try? mcSession.send(pageNumberData, toPeers: mcSession.connectedPeers, with: .reliable)
        }
    }
}

extension PDFPageSynchronizer: MCSessionDelegate, MCBrowserViewControllerDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case MCSessionState.connected:
            print("Connected: \(peerID.displayName)")
            DispatchQueue.main.async {
//                if self.testDataTimer == nil {
//                    self.testDataTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] (timer) in
//                        guard let self = self else { return }
//                        if !self.mcSession.connectedPeers.isEmpty, let data = try? NSKeyedArchiver.archivedData(withRootObject: Date(), requiringSecureCoding: false) {
//                            try? self.mcSession.send(data, toPeers: self.mcSession.connectedPeers, with: .reliable)
//                        }
//                    })
//                }
                print("Dismissing MP browser")
                self.presentingViewController?.dismiss(animated: true)
                self.mcBrowser = nil
            }

        case MCSessionState.connecting:
            print("Connecting: \(peerID.displayName)")
            
        case MCSessionState.notConnected:
            print("Not Connected: \(peerID.displayName)")
            if mcSession.connectedPeers.isEmpty {
//                testDataTimer.invalidate()
//                testDataTimer = nil
            }
        @unknown default:
            fatalError()
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("Received from \(peerID.displayName): \(data)")
        if let receivedDate = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? Date {
            print("Received from \(peerID.displayName): \(receivedDate)")
        }
        
        if let incomingPageNumber = data.withUnsafeBytes ({ (ptr:UnsafeRawBufferPointer) -> Int32? in
            let otherPtr = ptr.bindMemory(to: Int32.self)
            return otherPtr.first
            }) {
            print("Received page number \(incomingPageNumber)")
            presentingViewController?.pdfPageSynchronizer(self, didReceivePage: Int(incomingPageNumber))
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("Received stream from \(peerID.displayName): \(stream)")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        print("Started receiving from \(peerID.displayName): \(resourceName)")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        print("Finished receiving from \(peerID.displayName): \(resourceName)")
    }
    
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        print("Dismissing MP browser")
        presentingViewController?.dismiss(animated: true)
        mcBrowser = nil
    }
    
    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        print("Dismissing MP browser")
        presentingViewController?.dismiss(animated: true)
        mcBrowser = nil
    }
}
