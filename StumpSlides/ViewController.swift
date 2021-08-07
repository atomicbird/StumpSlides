//
//  ViewController.swift
//  StumpSlides
//
//  Created by Tom Harrington on 8/13/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import UIKit
import PDFKit
import UniformTypeIdentifiers
import AVKit

class ViewController: UIViewController {
    enum UserDefaultsKeys: String {
        case urlBookmark
    }
    
    var documentURL: URL? = nil
    var pdfDocument: PDFDocument!
    var documentDownloadInProgress = false {
        didSet {
            // Show/hide the iCloud download alert
            if documentDownloadInProgress {
                guard iCloudDownloadingView.superview == nil else { return }
                view.addSubview(iCloudDownloadingView)
                NSLayoutConstraint.activate([view.centerXAnchor.constraint(equalTo: iCloudDownloadingView.centerXAnchor),
                                             view.centerYAnchor.constraint(equalTo: iCloudDownloadingView.centerYAnchor)
                                            ])
                view.bringSubviewToFront(iCloudDownloadingView)
            } else {
                iCloudDownloadingView.removeFromSuperview()
            }
        }
    }
    var pdfView: PDFView!
    var pdfThumbnailView: PDFThumbnailView!
    var pdfThumbnailScrollView: UIScrollView!
    var thumbnailContainerView: UIView!

    var stumpmojiWatcher: StumpmojiWatcher!
    var stumpMojis: StumpmojiView!

    let useThumbnailScrollView = true
    let usePageSynchronizer = true

    let thumbnailSize: Int = 150
    // Without some extra padding, PDFThumbnailView has geometry trouble with PDFs more than around 20 pages long when the scroll view is used. Tapping on a thumbnail may bring up an adjacent page instead of the tapped page, and the enlarged "selected" view of the thumbnail will be off center. This was reported in FB7379442, 2019-10-15.
    // Adding a little horizontal padding gets normal behavior on iOS 13.1 but this is not documented and is something I found by experimenting.
    let pdfThumbnailPerPagePadding = 2
    lazy var pdfThumbnailEndPadding: Int = { return thumbnailSize / 2 }()
    
    var pageSynchronizer: PDFPageSynchronizer?
    var skipNextPageChangeNotification = false
    
    var menuVisible = false
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet var menuButtons: [UIButton]! {
        didSet {
            menuButtons.forEach {
                $0.setTitleColor(.black, for: .normal)
                $0.isHidden = true
            }
        }
    }
    @IBOutlet weak var menuBackground: UIView! {
        didSet {
            menuBackground.backgroundColor = .clear
            menuBackground.layer.cornerRadius = 10.0
        }
    }
    @IBOutlet weak var menuContainer: UIStackView!
    @IBOutlet weak var menuControlButton: UIButton! {
        didSet {
            let image = UIImage(systemName: "line.horizontal.3")
            menuControlButton.setTitle("", for: .normal)
            menuControlButton.setImage(image, for: .normal)
        }
    }
    @IBOutlet weak var scoreStack: UIStackView!
    @IBOutlet weak var panelScore: UILabel!
    @IBOutlet weak var attendeeScore: UILabel!
    
    @IBOutlet var iCloudDownloadingView: UIView! {
        didSet {
            iCloudDownloadingView.translatesAutoresizingMaskIntoConstraints = false
            iCloudDownloadingView.layer.cornerRadius = 10.0
        }
    }
    
    @IBOutlet weak var byteGameButton: UIButton!
    var stumpScore = StumpScores() {
        didSet {
            panelScore.text = String(stumpScore.panelScore)
            attendeeScore.text = String(stumpScore.audienceScore)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add PDF view
        pdfView = PDFView(frame: view.bounds)
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.autoScales = true
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = .black
        view.addSubviewAndConstrain(pdfView)
        
        // Add thumbnails but hide them for now. First the actual thumbnail viewer.
        pdfThumbnailView = PDFThumbnailView()
        pdfThumbnailView.translatesAutoresizingMaskIntoConstraints = false
        pdfThumbnailView.pdfView = pdfView
        pdfThumbnailView.layoutMode = .horizontal
        pdfThumbnailView.thumbnailSize = CGSize(width: thumbnailSize, height: thumbnailSize)
        pdfThumbnailView.backgroundColor = .clear

        if useThumbnailScrollView {
            NSLayoutConstraint.activate([
                pdfThumbnailView.heightAnchor.constraint(equalToConstant: CGFloat(thumbnailSize))
                // Width will be set when a PDF is loaded
            ])
            // Add a scroll view to hold the thumbnail view
            pdfThumbnailScrollView = UIScrollView()
            pdfThumbnailScrollView.translatesAutoresizingMaskIntoConstraints = false
            pdfThumbnailScrollView.backgroundColor = .clear
            pdfThumbnailScrollView.addSubview(pdfThumbnailView)
            pdfThumbnailScrollView.indicatorStyle = .white
            pdfThumbnailScrollView.alpha = 0
            
            NSLayoutConstraint.activate([
                pdfThumbnailView.leadingAnchor.constraint(equalTo: pdfThumbnailScrollView.leadingAnchor, constant: CGFloat(pdfThumbnailEndPadding)),
                pdfThumbnailView.trailingAnchor.constraint(equalTo: pdfThumbnailScrollView.trailingAnchor, constant: CGFloat(-pdfThumbnailEndPadding)),
                pdfThumbnailView.topAnchor.constraint(equalTo: pdfThumbnailScrollView.topAnchor),
                pdfThumbnailView.bottomAnchor.constraint(equalTo: pdfThumbnailScrollView.bottomAnchor)
            ])
            
            // Add the scroll view to the hierarchy at the bottom of the screen.
            view.addSubview(pdfThumbnailScrollView)
            NSLayoutConstraint.activate([
                pdfThumbnailScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                pdfThumbnailScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                pdfThumbnailScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                pdfThumbnailScrollView.heightAnchor.constraint(equalToConstant: CGFloat(thumbnailSize))
            ])
            thumbnailContainerView = pdfThumbnailScrollView
        } else {
            view.addSubview(pdfThumbnailView)
            
            NSLayoutConstraint.activate([
                pdfThumbnailView.heightAnchor.constraint(equalToConstant: CGFloat(thumbnailSize)),
                pdfThumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                pdfThumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                pdfThumbnailView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            
            pdfThumbnailView.alpha = 0
            thumbnailContainerView = pdfThumbnailView
        }

        // Add tap gesture to show/hide thumbnails
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(pdfViewTapped))
        pdfView.addGestureRecognizer(tapGestureRecognizer)
        
        // Add overlay to show incoming messages
        stumpMojis = StumpmojiView(frame: view.bounds)
        view.addSubviewAndConstrain(stumpMojis)

        // Set up message listener
        stumpmojiWatcher = StumpmojiWatcher()
        stumpmojiWatcher.stumpmojiReceived = { (message) in
            self.stumpMojis.addMessage(message)
        }
        stumpmojiWatcher.scoreReceived = { (incomingScore) in
            logMilestone("Received \(incomingScore)")
            self.stumpScore = incomingScore
        }
        stumpmojiWatcher.startWatching()
        
        if usePageSynchronizer {
            pageSynchronizer = PDFPageSynchronizer(with: self)
        }

        loadPreviousDocument()

        // This notification is posted
        // - When the PDFView's "document" property is set. The page is page 0.
        // - When state restoration happens.
        // - When the user moves to a new page.
        NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: nil, queue: OperationQueue.main) { [weak self] (notification) in
            logMilestone("Page change notification")
            self?.stopToThink()
            guard let self = self else { return }
            // Ignore a page change notification that happens when loading a PDF (when assigning to pdfView.document). Page sync messages should only be sent when the user changes the page.
            guard !self.skipNextPageChangeNotification else {
                self.skipNextPageChangeNotification = false
                return
            }
            logMilestone("PDF page change: \(notification)")
            logMilestone("Current page: \(String(describing: self.pdfView.currentPage))")
            logMilestone("Visible pages: \(self.pdfView.visiblePages)")
            if let currentPage = self.pdfView.currentPage {
                let pageIndex = self.pdfDocument.index(for: currentPage)
                logMilestone("Sending page index: \(pageIndex)")
                self.pageSynchronizer?.send(pageNumber: pageIndex)
            }
        }
        
        NotificationCenter.default.addObserver(forName: .PDFViewDocumentChanged, object: nil, queue: OperationQueue.main) { [weak self] (_) in
            self?.skipNextPageChangeNotification = true
            logMilestone("PDF document changed")
        }
        
        disconnectButton.isEnabled = false
        view.bringSubviewToFront(menuBackground)
        view.bringSubviewToFront(byteGameButton)
        view.bringSubviewToFront(scoreStack)
    }
    
    /// If there's a bookmark to a previously viewed document, and it still works, load that PDF.
    func loadPreviousDocument() -> Void {
        var bookmarkURL: URL? = nil
        // Resolve the bookmark to the last seen document
        if let bookmarkData = UserDefaults.standard.data(forKey: UserDefaultsKeys.urlBookmark.rawValue) {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale)
                if !isStale {
                    bookmarkURL = url
                }
            } catch {
                logMilestone("Error resolving bookmark: \(error)")
            }
        }

        // If the bookmark produced a working URL, load the document. Else ask the user to open something.
        if let bookmarkURL = bookmarkURL {
            load(documentURL: bookmarkURL)
        }
    }
    
    // Keep a reference to this constraint so it can be changed when loading a new PDF.
    var pdfThumbnailWidthConstraint: NSLayoutConstraint?
    
    /// Load a PDF from the URL. The URL may be security scoped, for example if it refers to a document on iCloud Drive
    /// - Parameter documentURL: URL pointing to a PDF
    func load(documentURL: URL) -> Void {
        // Stop accessing any currently loaded document
        if let previousDocumentURL = self.documentURL {
            previousDocumentURL.stopAccessingSecurityScopedResource()
        }
        guard documentURL.startAccessingSecurityScopedResource() else {
            logMilestone("Couldn't access URL \(documentURL)")
            return
        }
        
        // Uncomment this ONLY during debugging
//        do {
//            try FileManager.default.evictUbiquitousItem(at: documentURL)
//        } catch {
//            logMilestone("Error evicting document: \(error)")
//        }
        
        do {
            // N.B. you don't get valid results for resource values until after you stopAccessingSecurityScopedResource.
            let documentCloudInfo = try documentURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            if let isUbiquitous = documentCloudInfo.isUbiquitousItem, isUbiquitous, documentCloudInfo.ubiquitousItemDownloadingStatus != .current {
                logMilestone("Need to download ubiquitous item at \(documentURL)")
                downloadUbiquitousItemAt(url: documentURL)
                return
            }
        } catch {
            logMilestone("Error checking or downloading iCloud file: \(error)")
        }
        
        loadValidated(documentURL: documentURL)
    }
    
    func loadValidated(documentURL: URL) -> Void {
        guard let pdfDocument = PDFDocument(url: documentURL) else {
            logMilestone("Couldn't load document at \(documentURL)")
            return
        }
        self.documentURL = documentURL
        self.pdfDocument = pdfDocument
        pdfView.document = pdfDocument
        
        // Constrain the thumbnail view width based on the current document
        if let pdfThumbnailWidthConstraint = pdfThumbnailWidthConstraint {
            pdfThumbnailWidthConstraint.constant = CGFloat(pdfDocument.pageCount*(thumbnailSize + pdfThumbnailPerPagePadding))
        } else {
            let pdfThumbnailWidthConstraint = pdfThumbnailView.widthAnchor.constraint(equalToConstant: CGFloat(pdfDocument.pageCount*(thumbnailSize + pdfThumbnailPerPagePadding)))
            NSLayoutConstraint.activate([pdfThumbnailWidthConstraint])
            self.pdfThumbnailWidthConstraint = pdfThumbnailWidthConstraint
        }

        // Save a new bookmark for later use. If this fails we'll have to open the document again next time.
        do {
            let bookmark = try documentURL.bookmarkData()
            UserDefaults.standard.set(bookmark, forKey: UserDefaultsKeys.urlBookmark.rawValue)
        } catch {
            logMilestone("Error reading file: \(error)")
        }
    }
    
    func downloadUbiquitousItemAt(url: URL) {
        do {
            let downloadInfo = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadRequestedKey])
            logMilestone("Download info: requested = \(String(describing: downloadInfo.ubiquitousItemDownloadRequested)), status = \(String(describing: downloadInfo.ubiquitousItemDownloadingStatus)), downloading = \(String(describing: downloadInfo.ubiquitousItemIsDownloading))")
            // Return if we already asked for the download
            if let downloadRequested = downloadInfo.ubiquitousItemDownloadRequested, downloadRequested { return }
            // Return if it's already downloaded
            if let downloadStatus = downloadInfo.ubiquitousItemDownloadingStatus, downloadStatus == .current { return }
            // Return if it's currently downloading
            if let downloading = downloadInfo.ubiquitousItemIsDownloading, downloading { return }
            // Start downloading
            documentDownloadInProgress = true
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] (timer) in
                do {
                    let downloadStatus = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    logMilestone("Download status: \(String(describing: downloadStatus.ubiquitousItemDownloadingStatus))")
                    if downloadStatus.ubiquitousItemDownloadingStatus == .current {
                        timer.invalidate()
                        self?.loadValidated(documentURL: url)
                        self?.documentDownloadInProgress = false
                    }
                } catch {
                    logMilestone("Error checking download status: \(error)")
                    self?.documentDownloadInProgress = false
                }
            }
        } catch {
            logMilestone("Error starting iCloud download: \(error)")
            openDocument()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // If we didn't load a previously-viewed document, ask the user to open something.
        if pdfDocument == nil, !documentDownloadInProgress {
            openDocument()
        }
        logMilestone()
        
        if let byteGameVC = byteGameController {
            byteGameScores = (speakers:byteGameVC.speakerScore, attendees:byteGameVC.attendeeScore)
        }
    }

    override var prefersStatusBarHidden: Bool { return true }
    
    func showOrHide(view: UIView) -> Void {
        let newAlpha: CGFloat = {
            if view.alpha < 0.5 {
                return 1.0
            } else {
                return 0.0
            }
        }()
        UIView.animate(withDuration: 0.3) {
            view.alpha = newAlpha
        }
    }
    @objc func pdfViewTapped() -> Void {
        showOrHide(view: thumbnailContainerView)
    }

    @IBAction func browseForPeers(_ sender: Any) {
        pageSynchronizer?.startSyncing()
        pageSynchronizer?.browseForPeers()
        showHideMenu()
    }
    
    @IBAction func disconnectFromPeers(_ sender: Any) {
        pageSynchronizer?.disconnectFromPeers()
        showHideMenu()
    }
    
    @IBAction func showHideMenu() {
        self.menuButtons.forEach {
            $0.isHidden.toggle()
        }
        menuVisible.toggle()
        if menuVisible {
            menuBackground.backgroundColor = UIColor(white: 1.0, alpha: 0.6)
            menuControlButton.tintColor = .black
        } else {
            menuBackground.backgroundColor = .clear
            menuControlButton.tintColor = .white
        }
    }
    
    @IBAction func openDocument() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf])
        documentPicker.allowsMultipleSelection = false
        documentPicker.shouldShowFileExtensions = true
        documentPicker.delegate = self
        self.modalPresentationStyle = .fullScreen
        present(documentPicker, animated: true, completion: nil)
        showHideMenu()
    }

    lazy var thinkingVC: AVPlayerViewController = {
        let controller = AVPlayerViewController()
        guard let url = Bundle.main.url(forResource: "Thinking", withExtension: "mov") else { fatalError() }
        let player = AVPlayer(url: url)
        controller.player = player
        controller.showsPlaybackControls = false

        return controller
    }()
    
    let stopToThinkProbability = 0.1
    
    func stopToThink() -> Void {
        guard presentedViewController == nil else { return }
        
        let limit: Double = 100
        guard Double.random(in: 1...limit) < stopToThinkProbability * 100.0 else { return }
        
        present(thinkingVC, animated: false) {
            self.thinkingVC.player?.play()
        }
        
        let observerRef = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: thinkingVC.player?.currentItem, queue: OperationQueue.main) { [weak self] notification in
            print("Notification: \(notification)")
            self?.thinkingVC.player?.currentItem?.seek(to: CMTime.zero) { _ in
                self?.thinkingVC.player?.play()
            }
        }

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            self.thinkingVC.dismiss(animated: false) {
                self.thinkingVC.player?.pause()
            }
            NotificationCenter.default.removeObserver(observerRef)
        }
    }
    
    var byteGameController: ByteGameViewController?
    var byteGameScores: (speakers:Int, attendees:Int)?
    
    @IBAction func showByteGame(_ sender: Any) {
        guard let byteGameVC = byteGameController ?? self.storyboard?.instantiateViewController(withIdentifier: "ByteGameViewController") as? ByteGameViewController else { return }
        byteGameController = byteGameVC
        if let previousScores = byteGameScores {
            byteGameController?.attendeeScore = previousScores.attendees
            byteGameController?.speakerScore = previousScores.speakers
        }
        
        addChild(byteGameVC)
        byteGameVC.view.frame = view.bounds
        byteGameVC.view.translatesAutoresizingMaskIntoConstraints = false
        byteGameVC.view.alpha = 0.0
        view.addSubview(byteGameVC.view)
        view.bringSubviewToFront(byteGameVC.view)
        
        // Constraints are applied by ByteGameViewController's `didMove(toParent:)`.
        
        byteGameVC.didMove(toParent: self)
        
        byteGameVC.dismissHandler = { (byteGameVC) in
            UIView.animate(withDuration: 0.3) {
                byteGameVC.view.alpha = 0.0
            } completion: { _ in
                byteGameVC.didMove(toParent: nil)
                byteGameVC.view.removeFromSuperview()
                byteGameVC.removeFromParent()
            }
        }
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard presses.count == 1, // Only one press at a time
              let press = presses.first,
              let pressedKey = press.key,
              pressedKey.modifierFlags == [] || pressedKey.modifierFlags == [.numericPad] // No modifiers (shift, ctrl) allowed
        else {
            super.pressesBegan(presses, with: event)
            return
        }
        guard let currentPage = self.pdfView.currentPage else { return }
        let pageIndex = self.pdfDocument.index(for: currentPage)

        if pressedKey.keyCode == .keyboardLeftArrow {
            if pageIndex > 0 {
                pdfView.go(to: pageIndex-1)
            }
        } else if pressedKey.keyCode == .keyboardRightArrow {
            if pageIndex < pdfDocument.pageCount {
                pdfView.go(to: pageIndex+1)
            }
        }
    }
    
    // MARK: - State Restoration
    enum StateRestorationKeys: String {
        case documentURLPath // URL is only saved to decide whether to restore the page number. URL bookmark resolution is handled elsewhere.
        case pageNumber
    }
    
    override func encodeRestorableState(with coder: NSCoder) {
        logMilestone()
        guard let currentPageNumber = pdfView.currentPageNumber else { return }
        coder.encode(documentURL?.path, forKey: StateRestorationKeys.documentURLPath.rawValue)
        coder.encode(currentPageNumber, forKey: StateRestorationKeys.pageNumber.rawValue)
    }
    
    override func decodeRestorableState(with coder: NSCoder) {
        // This happens after viewDidLoad but before viewDidAppear, so documentURL will tell us if we found a previous document.
        // We only use the URL path to decide if it's the same document here. Resolving URL bookmarks happens elsewhere.
        guard let savedPath = coder.decodeObject(forKey: StateRestorationKeys.documentURLPath.rawValue) as? String, savedPath == documentURL?.path
        else { return }
        let savedPageNumber = coder.decodeInteger(forKey: StateRestorationKeys.pageNumber.rawValue)
        if usePageSynchronizer {
            pageSynchronizer = PDFPageSynchronizer(with: self, pageNumber: savedPageNumber)
        }
        pdfView.go(to: savedPageNumber)
        logMilestone()
    }
}

// MARK: - PDFPageSynchronizerDelegate
extension ViewController: PDFPageSynchronizerDelegate {
    func pdfPageSynchronizer(_: PDFPageSynchronizer, didReceivePage page: Int) {
        DispatchQueue.main.async {
            if page <= self.pdfDocument.pageCount {
                self.pdfView.go(to: page)
            }
        }
    }
    
    var pdfDocumentPageCount: Int {
        return pdfDocument.pageCount
    }

    func pdfPageSynchronizerPeersUpdated(_: PDFPageSynchronizer) -> Void {
        disconnectButton.isEnabled = pageSynchronizer?.peerCount != 0
    }

}

extension ViewController: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        logMilestone("Document picker cancelled")
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        logMilestone("Document picker picked \(urls)")
        guard !urls.isEmpty else { return }
        load(documentURL: urls[0])
    }
}
