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
    // Padding at the leading and trailing edges of the thumbnail view. Purely aesthetic, no functional effect.
    lazy var pdfThumbnailEndPadding: Int = { return 0 }()
//    lazy var pdfThumbnailEndPadding: Int = { return thumbnailSize / 2 }()

    var pageSynchronizer: PDFPageSynchronizer?
    var skipNextPageChangeNotification = false
    
    var menuVisible = false {
        didSet {
            cheetahMenuContainer.isHidden = !menuVisible
        }
    }
    @IBOutlet weak var disconnectButton: UIButton!
    @IBOutlet var pdfContainer: UIView!
    @IBOutlet weak var scoreStack: UIStackView!
    @IBOutlet weak var panelScore: UILabel!
    @IBOutlet var showHideTimerButton: UIButton!
    @IBOutlet weak var attendeeScore: UILabel!
    @IBOutlet var windowBarContainer: UIView!
    @IBOutlet var windowBarImageView: UIImageView! {
        didSet {
            let rawWindowBarImage = UIImage(named: "Cheetah window bar.png")!
            let stretchableWindowBarImage = rawWindowBarImage.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 75, bottom: 0, right: 35))
            windowBarImageView.image = stretchableWindowBarImage
        }
    }
    @IBOutlet var menuBarTimeLabel: UILabel! {
        didSet {
            menuBarTimeLabel.text = menuBarDateFormatter.string(from: Date())
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.menuBarTimeLabel.text = self.menuBarDateFormatter.string(from: Date())
            }
        }
    }
    let menuBarDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()
    @IBOutlet var cheetahMenuBarImageView: UIImageView! {
        didSet {
            let rawMenuBarImage = UIImage(named: "Cheetah menu bar blank.png")!
            let stretchableMenuBarImage = rawMenuBarImage.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 36, bottom: 0, right: 10), resizingMode: .stretch)
            cheetahMenuBarImageView.image = stretchableMenuBarImage
        }
    }
    @IBOutlet var cheetahFileMenuButton: UIButton!
    @IBOutlet var cheetahMenuContainer: UIView! {
        didSet {
            let stripePattern = UIImage(named: "Cheetah stripes.png")!
            let backgroud = UIColor(patternImage: stripePattern)
            cheetahMenuContainer.backgroundColor = backgroud
        }
    }
    @IBOutlet var scoreContainerView: UIView! { didSet { scoreContainerView.isHidden = true }}
    @IBOutlet var scoreContainerBackground: UIImageView! {
        didSet {
            let rawStickiesBackground = UIImage(named: "stickies-background.png")!
            let stretchableStickiesBackground = rawStickiesBackground.resizableImage(withCapInsets: UIEdgeInsets(top: 12, left: 22, bottom: 0, right: 33), resizingMode: .stretch)
            scoreContainerBackground.image = stretchableStickiesBackground
        }
    }
    
    @IBOutlet var iCloudDownloadingView: UIView! {
        didSet {
            iCloudDownloadingView.translatesAutoresizingMaskIntoConstraints = false
            iCloudDownloadingView.layer.cornerRadius = 10.0
        }
    }
    
    @IBOutlet var scoreLabels: [UILabel]! // { didSet { scoreLabels.forEach { $0.alpha = 0 }}}
    var stumpScore = StumpScores() {
        didSet {
            panelScore.text = String(stumpScore[.panelScore])
            attendeeScore.text = String(stumpScore[.audienceScore])
            if stumpScore[.panelScore] != 0 || stumpScore[.audienceScore] != 0 {
                scoreContainerView.isHidden = false
            } else {
                scoreContainerView.isHidden = true
            }
        }
    }

    @IBOutlet weak var timerContainerView: UIView!
    lazy var timerViewController: TimerViewController = {
        guard let vc = storyboard?.instantiateViewController(withIdentifier: "TimerViewController") as? TimerViewController else { fatalError() }
        return vc
    }()
    
    @IBOutlet var emojiDemoButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor(patternImage: UIImage(named: "10-0_10.1.png")!)
//        let asdf = PDFAnnotation(bounds: <#T##CGRect#>, forType: <#T##PDFAnnotationSubtype#>, withProperties: <#T##[AnyHashable : Any]?#>)
        // Add PDF view
        pdfView = PDFView(frame: view.bounds)
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.autoScales = true
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = .white
        
        // Make PDFView equal to view's width, centered horizontally, with a 16:9 aspect ratio
        pdfContainer.addSubviewAndConstrain(pdfView)
        
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
            pageSynchronizer = PDFPageSynchronizer(delegate: self)
        }

        loadPreviousDocument()

        // This notification is posted
        // - When the PDFView's "document" property is set. The page is page 0.
        // - When state restoration happens.
        // - When the user moves to a new page.
        NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: nil, queue: OperationQueue.main) { [weak self] (notification) in
            logMilestone("Page change notification")
                // Sometimes the PDF view doesn't update when stopping to think and sending a page. The thumbnail view does update, though. Dispatching to main here doesn't fix it.
            self?.showBeachball()
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
//                self.pdfView.go(to: currentPage)
//                self.pdfView.setNeedsDisplay()
                let pageIndex = self.pdfDocument.index(for: currentPage)
                logMilestone("Sending page index: \(pageIndex)")
                self.pageSynchronizer?.send(pageNumber: pageIndex)
            }
            
            DispatchQueue.main.async {
                self.pdfView.setNeedsLayout()
            }
        }
        
        NotificationCenter.default.addObserver(forName: .PDFViewDocumentChanged, object: nil, queue: OperationQueue.main) { [weak self] (_) in
            self?.skipNextPageChangeNotification = true
            logMilestone("PDF document changed")
        }
        
        cheetahMenuContainer.translatesAutoresizingMaskIntoConstraints = false
        cheetahMenuContainer.isHidden = true
        view.addSubview(cheetahMenuContainer)
        NSLayoutConstraint.activate([
            cheetahMenuContainer.topAnchor.constraint(equalTo: cheetahMenuBarImageView.bottomAnchor, constant: 0),
            cheetahMenuContainer.leadingAnchor.constraint(equalTo: cheetahFileMenuButton.leadingAnchor)
        ])
        
        disconnectButton.isEnabled = false
        view.bringSubviewToFront(scoreStack)
        view.bringSubviewToFront(emojiDemoButton)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        addShadowPath(to: cheetahMenuContainer)
        addShadowPath(to: scoreContainerView)
        addShadowPath(to: pdfContainer)
    }
    
    func addShadowPath(to viewToShadow:  UIView) -> Void {
        viewToShadow.layer.shadowColor = UIColor.darkGray.cgColor
        viewToShadow.layer.shadowOpacity = 1
        viewToShadow.layer.shadowOffset = .zero
        viewToShadow.layer.shadowRadius = 7

        let shadowPath = CGMutablePath()
        shadowPath.move(to: CGPoint(x: viewToShadow.bounds.minX, y: viewToShadow.bounds.minY))
        shadowPath.addLine(to: CGPoint(x: viewToShadow.bounds.minX, y: viewToShadow.bounds.maxY))
        shadowPath.addLine(to: CGPoint(x: viewToShadow.bounds.maxX, y: viewToShadow.bounds.maxY))
        shadowPath.addLine(to: CGPoint(x: viewToShadow.bounds.maxX, y: viewToShadow.bounds.minY))
        viewToShadow.layer.shadowPath = shadowPath
    }
    
    override func buildMenu(with builder: UIMenuBuilder) {
        // Not getting called
        super.buildMenu(with: builder)
        builder.remove(menu: UIMenu.Identifier.file)
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
        
        pageSynchronizer?.updateHosting()
        
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
    
    lazy var introVideoVC: AVPlayerViewController = {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = true
        controller.delegate = self
        return controller
    }()
    var introVideoLoopingObserver: Any?
    
    func play(video videoURL: URL) {
        guard videoURL.startAccessingSecurityScopedResource() else {
            print("Could not access url \(videoURL)")
            return
        }
        let player = AVPlayer(url: videoURL)
        introVideoVC.player = player
        
        stumpMojis.removeFromSuperview()
        introVideoVC.contentOverlayView?.addSubviewAndConstrain(stumpMojis)
        
        present(introVideoVC, animated: false) {
            self.introVideoVC.player?.play()
        }
        
        // Looping isn't built in so do this to replay when the video ends
        introVideoLoopingObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: introVideoVC.player?.currentItem, queue: .main) { [weak self] _ in
            self?.introVideoVC.player?.currentItem?.seek(to: .zero) { _ in
                self?.introVideoVC.player?.play()
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder() // Make sure keyboard presses work
        // If we didn't load a previously-viewed document, ask the user to open something.
        if pdfDocument == nil, !documentDownloadInProgress {
            openDocument()
        }
        logMilestone()
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
        menuVisible = false
    }

    @IBAction func browseForPeers(_ sender: Any) {
        pageSynchronizer?.browseForPeers(presentingViewController: self)
        showHideMenu()
    }
    
    @IBAction func disconnectFromPeers(_ sender: Any) {
        pageSynchronizer?.disconnectFromPeers()
        showHideMenu()
    }
    
    @IBAction func showHideMenu() {
        menuVisible.toggle()
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

    @IBAction func openVideo(_ sender: Any) {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.video, .movie])
        documentPicker.allowsMultipleSelection = false
        documentPicker.shouldShowFileExtensions = true
        documentPicker.delegate = self
        self.modalPresentationStyle = .fullScreen
        present(documentPicker, animated: true, completion: nil)
        showHideMenu()
    }
    
    let shoeBeachballProbability = 0.1
    let showBeachballTime = 2
    
    var beachballImages: [UIImage] = {
        var images = [UIImage]()
        images.append(contentsOf: [
            UIImage(named: "spinning-beachball 2.png")!,
            UIImage(named: "spinning-beachball 3.png")!,
            UIImage(named: "spinning-beachball 4.png")!,
            UIImage(named: "spinning-beachball 5.png")!,
            UIImage(named: "spinning-beachball 6.png")!,
            UIImage(named: "spinning-beachball 7.png")!,
            UIImage(named: "spinning-beachball 8.png")!,
            UIImage(named: "spinning-beachball 9.png")!,
            UIImage(named: "spinning-beachball 10.png")!,
            UIImage(named: "spinning-beachball 11.png")!,
            UIImage(named: "spinning-beachball 12.png")!,
            UIImage(named: "spinning-beachball.png")!,
        ])
        return images
    }()
    var beachballImageView: UIImageView?
    var beachballView: UIView?
    
    func showBeachball() -> Void {
        let limit: Double = 100
        guard Double.random(in: 1...limit) < shoeBeachballProbability * 100.0 else { return }

        if beachballImageView == nil {
            let background = UIView(frame: pdfContainer.frame)
            background.backgroundColor = .white
            beachballView = background
            
            let ballView = UIImageView(frame: pdfContainer.frame)
            ballView.animationImages = beachballImages
            ballView.animationDuration = 1
            ballView.contentMode = .scaleAspectFit
            ballView.backgroundColor = .white
            beachballImageView = ballView
            
            background.addSubviewAndConstrain(ballView, inset: UIEdgeInsets(top: -40, left: 0, bottom: 40, right: 0))
        }
        
        pdfContainer.addSubviewAndConstrain(beachballView!)
        pdfContainer.bringSubviewToFront(beachballView!)
        beachballImageView?.startAnimating()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(showBeachballTime)) {
            self.beachballView?.removeFromSuperview()
        }
    }
    
    @IBAction func timerButtonPressed(_ sender: Any) {
        if timerViewController.parent != self {
            showTimer()
        } else {
            hideTimer()
        }
    }
    
    @IBAction func addSomeEmoji(_ sender: Any) {
        stumpMojis.addRandomMessages()
    }
    
    func showTimer() {
        addChild(timerViewController)
        timerViewController.initialTimes = [60, 5*60, 10*60, 15*60]
        timerViewController.view.frame = timerContainerView.bounds
        timerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        timerContainerView.addSubviewAndConstrain(timerViewController.view)
        view.bringSubviewToFront(timerContainerView)
        timerViewController.didMove(toParent: self)
        showHideTimerButton.setTitle("Hide Timer", for: .normal)
    }
    
    func hideTimer() {
        timerViewController.didMove(toParent: nil)
        timerViewController.view.removeFromSuperview()
        timerViewController.removeFromParent()
        showHideTimerButton.setTitle("Show Timer", for: .normal)
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
        } else {
            super.pressesBegan(presses, with: event)
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
            if pageSynchronizer == nil {
                pageSynchronizer = PDFPageSynchronizer(delegate: self, pageNumber: savedPageNumber)
                pageSynchronizer?.startHosting()
            } else {
                pageSynchronizer?.updateHosting()
            }
        }
        pdfView.go(to: savedPageNumber)
        logMilestone()
    }
}

// MARK: - PDFPageSynchronizerDelegate
extension ViewController: PDFPageSynchronizerDelegate {
    func pdfPageSynchrinizer(_: PDFPageSynchronizer, postedStatus: String) {
        logMilestone("Page sync message: \(postedStatus)")
    }
    
    func pdfPageSynchronizer(_: PDFPageSynchronizer, didReceivePage page: Int) {
        DispatchQueue.main.async {
            if page <= self.pdfDocument.pageCount {
                self.pdfView.go(to: page)
            }
        }
    }
    
    var pdfDocumentPageCount: Int? {
        return pdfDocument?.pageCount
    }

    func pdfPageSynchronizerPeersUpdated(_: PDFPageSynchronizer) -> Void {
        disconnectButton.isEnabled = pageSynchronizer?.connected ?? false
    }

}

extension ViewController: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        logMilestone("Document picker cancelled")
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        logMilestone("Document picker picked \(urls)")
        guard !urls.isEmpty else { return }
        let url = urls[0]
        
        guard url.startAccessingSecurityScopedResource(),
            let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let contentType = resourceValues.contentType
        else { return }
        url.stopAccessingSecurityScopedResource()
        if contentType.conforms(to: .pdf) {
            load(documentURL: urls[0])
        } else if contentType.conforms(to: .video) || contentType.conforms(to: .movie) {
            play(video: url)
        }
    }
}

extension ViewController: AVPlayerViewControllerDelegate {
    func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        logMilestone("View controller ending full screen")
        if let introVideoLoopingObserver = introVideoLoopingObserver {
            NotificationCenter.default.removeObserver(introVideoLoopingObserver)
        }
        stumpMojis.removeFromSuperview()
        view.addSubviewAndConstrain(stumpMojis)
        view.bringSubviewToFront(stumpMojis)
    }
}
