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
    func pdfPageSynchrinizer(_: PDFPageSynchronizer, postedStatus: String) -> Void
    var pdfDocumentPageCount: Int? { get }
}

/// Synchronize the current page across two or more instances of the app running on different devices, via Multipeer networking.
class PDFPageSynchronizer: NSObject {
    var peerID: MCPeerID!
    var mcSession: MCSession!
    var mcAdvertiser: MCNearbyServiceAdvertiser?
    var testDataTimer: Timer!
    var mcBrowserVC: MCBrowserViewController!
    var mcBrowser: MCNearbyServiceBrowser?
    
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
    
    // This probably doesn't need to be a view controller anymore.
//    var presentingViewController: (UIViewController & PDFPageSynchronizerDelegate)
    var delegate: PDFPageSynchronizerDelegate
    
    enum DiscoveryInfoKeys: String {
        case pageCount
    }
    var discoveryInfo: [String:String] = [:]
    
    init(delegate: PDFPageSynchronizerDelegate, pageNumber: Int = 0) {
        self.delegate = delegate
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
    

    // The service name needs to be 1-15 chars, only lowercase ASCII letters, numbers, or hyphens. Full rules are currently found in the MCAdvertiserAssistant documentation or apparently RFC 6335.
    // Service name ALSO must match the one declared in Info.plist under NSBonjourServices, stripped of the Bonjour-y details. If Info.plist has "_stump360._tcp", the service name here must me "stump360".
    lazy var serviceType: String = {
        logMilestone()
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
    
    /// Start advertising that hosting is available and start browsing for peers. Peers are invited automatically when discovered.
    func startHosting() {
        logMilestone()
        guard let pageCount = delegate.pdfDocumentPageCount else { return }
        discoveryInfo = [DiscoveryInfoKeys.pageCount.rawValue: "\(pageCount)"]
        mcAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: discoveryInfo, serviceType: serviceType)
        mcAdvertiser?.delegate = self
        mcAdvertiser?.startAdvertisingPeer()
        
        guard mcBrowser == nil else { return }
        mcBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        mcBrowser?.delegate = self
        mcBrowser?.startBrowsingForPeers()
    }
    
    /// Disconnect from peers and then restart advertising. Use this if the document or page count changes
    func updateHosting() {
        logMilestone()
        mcAdvertiser?.stopAdvertisingPeer()
        mcAdvertiser = nil
        mcBrowser?.stopBrowsingForPeers()
        mcBrowser = nil
        
        disconnectFromPeers()
        startHosting()
    }
    
    /// Look for any other nearby hosts advertising the same service, using the framework's default UIVC. This shouldn't be necessary since connections are automatic, but may be useful if that fails for some reason.
    func browseForPeers(presentingViewController: UIViewController) {
        guard mcBrowserVC == nil else { return }
        mcBrowserVC = MCBrowserViewController(serviceType: serviceType, session: mcSession)
        mcBrowserVC.delegate = self
        DispatchQueue.main.async {
            presentingViewController.present(self.mcBrowserVC, animated: true)
        }
    }
    
    /// Disconnect from current peers but don't stop advertising
    func disconnectFromPeers() {
        mcSession.disconnect()
        DispatchQueue.main.async {
            self.delegate.pdfPageSynchronizerPeersUpdated(self)
        }
    }
    
    var peerCount: Int { return mcSession.connectedPeers.count }
    
    fileprivate func send(_ pageSend: PageSend) -> Void {
        logMilestone("Asked to send page \(pageSend.pageNumber) with type \(pageSend.sendType.rawValue)")
        if !self.mcSession.connectedPeers.isEmpty {
            guard let encodedPageSend = try? JSONEncoder().encode(pageSend) else { return }
            logMilestone("Sending page \(pageSend.pageNumber) with type \(pageSend.sendType.rawValue) (\(encodedPageSend))")
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
                if self.mcBrowserVC != nil {
                    logMilestone("Dismissing MP browser: connected")
                    self.mcBrowserVC.presentingViewController?.dismiss(animated: true) {
                        self.mcBrowserVC = nil
                    }
                }
                
                // Send the current page to the other connected devices so that everyone can get on the same page.
                let connectPageSend = PageSend(pageNumber: self.lastPageSend.pageNumber, startDate: self.startDate, sendType: .connection)
                self.send(connectPageSend)
                
                self.delegate.pdfPageSynchrinizer(self, postedStatus: "Connected to \(peerID.displayName)")
                self.delegate.pdfPageSynchronizerPeersUpdated(self)
            }

        case MCSessionState.connecting:
            logMilestone("Connecting: \(peerID.displayName)")
            
        case MCSessionState.notConnected:
            logMilestone("Not Connected: \(peerID.displayName)")
            DispatchQueue.main.async {
                self.delegate.pdfPageSynchrinizer(self, postedStatus: "Disconnected from \(peerID.displayName)")
                self.delegate.pdfPageSynchronizerPeersUpdated(self)
            }
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
            DispatchQueue.main.async {
                self.delegate.pdfPageSynchronizer(self, didReceivePage: incomingPageSend.pageNumber)
            }
        } else if incomingPageSend.sendType == .pageChange {
            logMilestone("Updating local page (change)")
            self.lastPageSend.pageNumber = incomingPageSend.pageNumber
            DispatchQueue.main.async {
                self.delegate.pdfPageSynchronizer(self, didReceivePage: incomingPageSend.pageNumber)
            }
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

// MARK: - MCBrowserViewControllerDelegate
extension PDFPageSynchronizer: MCBrowserViewControllerDelegate {
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        logMilestone("Dismissing MP browser: finished")
        DispatchQueue.main.async {
            self.mcBrowserVC.presentingViewController?.dismiss(animated: true) {
                self.mcBrowserVC = nil
            }
        }
    }
    
    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        logMilestone("Dismissing MP browser: cancelled")
        DispatchQueue.main.async {
            self.mcBrowserVC.presentingViewController?.dismiss(animated: true) {
                self.mcBrowserVC = nil
            }
        }
    }
    
    func browserViewController(_ browserViewController: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) -> Bool {
        logMilestone("Checking whether to present \(peerID.displayName)")
        guard let discoveryInfo = info else { return false }
        // Compare the number of pages in the peer's document to the local document to decide if we should connect.
        guard let incomingPageCountString = discoveryInfo[DiscoveryInfoKeys.pageCount.rawValue],
            let incomingPageCount = Int(incomingPageCountString),
            incomingPageCount == delegate.pdfDocumentPageCount
            else { return false }
        return true
    }
}

extension PDFPageSynchronizer: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let peerName = peerID.displayName
        logMilestone("Received invitation from \(peerName)")
        invitationHandler(true, mcSession) // Always accept
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        logMilestone("Could not advertise MP service")
        updateHosting() // Try again?
    }
}

extension PDFPageSynchronizer: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Invite every peer
        logMilestone("Found peer \(peerID.displayName)")
        guard info != nil, info == discoveryInfo else {
            logMilestone("Not inviting peer \(peerID.displayName), discovery info mismatch")
            return
        }
        logMilestone("Inviting peer \(peerID.displayName)")
        browser.invitePeer(peerID, to: mcSession, withContext: nil, timeout: 30)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logMilestone("Lost connection to \(peerID.displayName)")
        DispatchQueue.main.async {
            self.delegate.pdfPageSynchrinizer(self, postedStatus: "Lost connection to \(peerID.displayName)")
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        logMilestone("Could not browse for peers")
        updateHosting() // Try again?
    }
}
