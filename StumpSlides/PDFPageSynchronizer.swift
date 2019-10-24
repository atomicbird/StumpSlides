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

/// Synchronize the current page across two or more instances of the app running on different devices, via Multipeer networking.
class PDFPageSynchronizer: NSObject {
    var peerID: MCPeerID!
    var mcSession: MCSession!
    var mcAdvertiserAssistant: MCAdvertiserAssistant!
    var testDataTimer: Timer!
    var mcBrowser: MCBrowserViewController!
    
    var startDate: Date!
    
    struct PageSend: Codable {
        enum CodingKeys: CodingKey {
            case pageNumber
            case startDate
            case sendType
        }

        var pageNumber: Int = 0
        var startDate: Date
        
        enum SendType: String, Codable {
            case connection
            case pageChange
        }
        var sendType: SendType = .pageChange
    }
    
    var lastPageSend: PageSend
    
    weak var presentingViewController: (UIViewController & PDFPageSynchronizerDelegate)?
    
    init(with viewController: UIViewController & PDFPageSynchronizerDelegate, pageNumber: Int = 0) {
        presentingViewController = viewController
        lastPageSend = PageSend(pageNumber: pageNumber, startDate: Date())
        super.init()
        setupMultipeer()
    }

    fileprivate func setupMultipeer() -> Void {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self
        startDate = lastPageSend.startDate
    }
    
    func startSyncing() -> Void {
        logMilestone()
        guard mcAdvertiserAssistant == nil else { return }
        startHostingMP()
        joinSessionMP()
    }
    
    // I couldn't find docs on what makes an acceptable service type with Multipeer networking, but word on the street (https://www.objc.io/issues/18-games/multipeer-connectivity-for-games/) says that it can't be more than 15 characters.
    // Bundle ID seems like a good idea except there's a good chance it's too long, so remove the dots from it and take the last 15 characters. Last 15 instead of first 15 because they seem more likely to be unique, e.g. if there's more than one app from the same company where multiple bundle IDs might start with "com.myverylongcompanyname....".
    lazy var serviceType: String = {
        return String(Bundle.main.bundleIdentifier!.replacingOccurrences(of: ".", with: "").suffix(15))
    }()
    
    fileprivate func startHostingMP() {
        mcAdvertiserAssistant = MCAdvertiserAssistant(serviceType: serviceType, discoveryInfo: nil, session: mcSession)
        mcAdvertiserAssistant.start()
    }

    fileprivate func joinSessionMP() {
        mcBrowser = MCBrowserViewController(serviceType: serviceType, session: mcSession)
        mcBrowser.delegate = self
        presentingViewController?.present(mcBrowser, animated: true)
    }
    
    fileprivate func send(_ pageSend: PageSend) -> Void {
        logMilestone("Asked to send page \(pageSend.pageNumber) with type \(pageSend.sendType.rawValue)")
        if !self.mcSession.connectedPeers.isEmpty {
            logMilestone("Sending page \(pageSend.pageNumber) with type \(pageSend.sendType.rawValue)")
            guard let encodedPageSend = try? JSONEncoder().encode(pageSend) else { return }
            do {
                try mcSession.send(encodedPageSend, toPeers: mcSession.connectedPeers, with: .reliable)
            } catch {
                logMilestone("Send error: \(error)")
            }
        }
    }
    
    func send(pageNumber: Int) -> Void {
        guard pageNumber != lastPageSend.pageNumber else { return }
        lastPageSend.pageNumber = pageNumber
        
        send(lastPageSend)
    }
}

// MARK: - MCSessionDelegate, MCBrowserViewControllerDelegate
extension PDFPageSynchronizer: MCSessionDelegate, MCBrowserViewControllerDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case MCSessionState.connected:
            logMilestone("Connected: \(peerID.displayName)")
            DispatchQueue.main.async {
                logMilestone("Dismissing MP browser")
                self.presentingViewController?.dismiss(animated: true)
                self.mcBrowser = nil

                // Send the current page to the other connected devices so that everyone can get on the same page.
                let connectPageSend = PageSend(pageNumber: self.lastPageSend.pageNumber, startDate: self.startDate, sendType: .connection)
                self.send(connectPageSend)
            }

        case MCSessionState.connecting:
            logMilestone("Connecting: \(peerID.displayName)")
            
        case MCSessionState.notConnected:
            logMilestone("Not Connected: \(peerID.displayName)")
        @unknown default:
            fatalError()
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        logMilestone("Received from \(peerID.displayName): \(data)")

        guard let incomingPageSend = try? JSONDecoder().decode(PageSend.self, from: data) else { return }
        logMilestone("Received page \(incomingPageSend.pageNumber), type = \(incomingPageSend.sendType.rawValue)")
        
        // Whichever device thinks it started earliest wins out for page number on initial connect.
        if incomingPageSend.sendType == .connection, incomingPageSend.startDate < startDate {
            logMilestone("Updating local page (connect)")
            self.lastPageSend = incomingPageSend
            presentingViewController?.pdfPageSynchronizer(self, didReceivePage: incomingPageSend.pageNumber)
        } else if incomingPageSend.sendType == .pageChange {
            logMilestone("Updating local page (change)")
            self.lastPageSend = incomingPageSend
            presentingViewController?.pdfPageSynchronizer(self, didReceivePage: incomingPageSend.pageNumber)
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        logMilestone("Received stream from \(peerID.displayName): \(stream)")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        logMilestone("Started receiving from \(peerID.displayName): \(resourceName)")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        logMilestone("Finished receiving from \(peerID.displayName): \(resourceName)")
    }
    
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        logMilestone("Dismissing MP browser")
        presentingViewController?.dismiss(animated: true)
        mcBrowser = nil
    }
    
    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        logMilestone("Dismissing MP browser")
        presentingViewController?.dismiss(animated: true)
        mcBrowser = nil
    }
}
