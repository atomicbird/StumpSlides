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
    func pdfPageSynchronizer(_: PDFPageSynchronizer, didReceivePage: Int) -> Void
    func pdfPageSynchronizerPeersUpdated(_: PDFPageSynchronizer) -> Void
    var pdfDocumentPageCount: Int { get }
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
    
    var presentingViewController: (UIViewController & PDFPageSynchronizerDelegate)
    
    enum DiscoveryInfoKeys: String {
        case pageCount
    }
    
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
    
    /// Start hosting and browsing
    func startSyncing() -> Void {
        logMilestone()
        guard mcAdvertiserAssistant == nil else { return }
        startHosting()
        browseForPeers()
    }

    // The service name needs to be 1-15 chars, only lowercase ASCII letters, numbers, or hyphens. Full rules are currently found in the MCAdvertiserAssistant documentation or apparently RFC 6335.
    // Service name ALSO must match the one declared in Info.plist under NSBonjourServices, stripped of the Bonjour-y details. If Info.plist has "_stump360._tcp", the service name here must me "stump360".
    lazy var serviceType: String = {
        // Expect an array where the first element is something like "_stump360._tcp"
        guard let bonjourServices = Bundle.main.infoDictionary?["NSBonjourServices"] as? [String],
              !bonjourServices.isEmpty,
              bonjourServices[0].hasSuffix("._tcp"),
              bonjourServices[0].first == "_"
        else {
            fatalError()
        }
        let bonjourService = bonjourServices[0]
        var mpService = bonjourServices[0].split(separator: ".")[0]
        mpService.removeFirst()
        return String(mpService)
    }()
    
    func startHosting() {
        let discoveryInfo = [DiscoveryInfoKeys.pageCount.rawValue: "\(presentingViewController.pdfDocumentPageCount)"]
        mcAdvertiserAssistant = MCAdvertiserAssistant(serviceType: serviceType, discoveryInfo: discoveryInfo, session: mcSession)
        mcAdvertiserAssistant.start()
    }

    func browseForPeers() {
        mcBrowser = MCBrowserViewController(serviceType: serviceType, session: mcSession)
        mcBrowser.delegate = self
        presentingViewController.present(mcBrowser, animated: true)
    }
    
    func disconnectFromPeers() {
        mcSession.disconnect()
        self.presentingViewController.pdfPageSynchronizerPeersUpdated(self)
    }
    
    var peerCount: Int { return mcSession.connectedPeers.count }
    
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

// MARK: - MCSessionDelegate
extension PDFPageSynchronizer: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case MCSessionState.connected:
            logMilestone("Connected: \(peerID.displayName)")
            DispatchQueue.main.async {
                logMilestone("Dismissing MP browser")
                self.presentingViewController.dismiss(animated: true)
                self.mcBrowser = nil

                // Send the current page to the other connected devices so that everyone can get on the same page.
                let connectPageSend = PageSend(pageNumber: self.lastPageSend.pageNumber, startDate: self.startDate, sendType: .connection)
                self.send(connectPageSend)
                
                self.presentingViewController.pdfPageSynchronizerPeersUpdated(self)
            }

        case MCSessionState.connecting:
            logMilestone("Connecting: \(peerID.displayName)")
            
        case MCSessionState.notConnected:
            logMilestone("Not Connected: \(peerID.displayName)")
            self.presentingViewController.pdfPageSynchronizerPeersUpdated(self)
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
            self.lastPageSend.pageNumber = incomingPageSend.pageNumber
            presentingViewController.pdfPageSynchronizer(self, didReceivePage: incomingPageSend.pageNumber)
        } else if incomingPageSend.sendType == .pageChange {
            logMilestone("Updating local page (change)")
            self.lastPageSend.pageNumber = incomingPageSend.pageNumber
            presentingViewController.pdfPageSynchronizer(self, didReceivePage: incomingPageSend.pageNumber)
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
}

// MARK: - MCSessionDelegate, MCBrowserViewControllerDelegate
extension PDFPageSynchronizer: MCBrowserViewControllerDelegate {
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        logMilestone("Dismissing MP browser")
        presentingViewController.dismiss(animated: true)
        mcBrowser = nil
    }
    
    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        logMilestone("Dismissing MP browser")
        presentingViewController.dismiss(animated: true)
        mcBrowser = nil
    }
    
    func browserViewController(_ browserViewController: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) -> Bool {
        guard let discoveryInfo = info else { return false }
        // Compare the number of pages in the peer's document to the local document to decide if we should connect.
        guard let incomingPageCountString = discoveryInfo[DiscoveryInfoKeys.pageCount.rawValue],
            let incomingPageCount = Int(incomingPageCountString),
            incomingPageCount == presentingViewController.pdfDocumentPageCount
            else { return false }
        return true
    }
}
