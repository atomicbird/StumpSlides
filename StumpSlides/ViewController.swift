//
//  ViewController.swift
//  StumpSlides
//
//  Created by Tom Harrington on 8/13/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import UIKit
import PDFKit

class ViewController: UIViewController {
    
    let pdfName = "TestSlides100.pdf"
//    let pdfName = "TestSlides50.pdf"
    var pdfDocument: PDFDocument!
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
    
    @IBOutlet weak var buttonContainer: UIView! {
        didSet {
            buttonContainer.layer.cornerRadius = 10.0
        }
    }
    @IBOutlet weak var disconnectButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Load PDF
        if let documentURL = Bundle.main.url(forResource: pdfName, withExtension: nil),
            let pdfDocument = PDFDocument(url: documentURL) {
            self.pdfDocument = pdfDocument
        } else {
            logMilestone("Couldn't load file \(pdfName)")
        }
        
        // Add PDF view
        pdfView = PDFView(frame: view.bounds)
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.autoScales = true
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = .black
        pdfView.document = pdfDocument
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
                pdfThumbnailView.heightAnchor.constraint(equalToConstant: CGFloat(thumbnailSize)),
                pdfThumbnailView.widthAnchor.constraint(equalToConstant: CGFloat(pdfDocument.pageCount*(thumbnailSize + pdfThumbnailPerPagePadding)))
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
        // Add double tap gesture to show/hide button overlay
        let doubleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(pdfViewDoubleTap))
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        pdfView.addGestureRecognizer(doubleTapGestureRecognizer)
        tapGestureRecognizer.require(toFail: doubleTapGestureRecognizer)
        
        // Add overlay to show incoming messages
        stumpMojis = StumpmojiView(frame: view.bounds)
        view.addSubviewAndConstrain(stumpMojis)

        // Set up message listener
        stumpmojiWatcher = StumpmojiWatcher()
        stumpmojiWatcher.stumpmojiReceived = { (message) in
            self.stumpMojis.addMessage(message)
        }
        stumpmojiWatcher.startWatching()
        
        if usePageSynchronizer {
            pageSynchronizer = PDFPageSynchronizer(with: self)
        }

        // This notification is posted
        // - When the PDFView's "document" property is set. The page is page 0.
        // - When state restoration happens.
        // - When the user moves to a new page.
        NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: nil, queue: OperationQueue.main) { [weak self] (notification) in
            logMilestone("Page change notification")
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
        
        buttonContainer.alpha = 0.0
        disconnectButton.isEnabled = false
        view.bringSubviewToFront(buttonContainer)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pageSynchronizer?.startSyncing()
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
    }
    
    @objc func pdfViewDoubleTap() -> Void {
        showOrHide(view: buttonContainer)
    }
    
    @IBAction func browseForPeers(_ sender: Any) {
        pageSynchronizer?.browseForPeers()
    }
    
    @IBAction func disconnectFromPeers(_ sender: Any) {
        pageSynchronizer?.disconnectFromPeers()
    }
    
    // MARK: - State Restoration
    enum StateRestorationKeys: String {
        case filename
        case pageNumber
    }
    
    override func encodeRestorableState(with coder: NSCoder) {
        guard let currentPageNumber = pdfView.currentPageNumber else { return }
        coder.encode(pdfName, forKey: StateRestorationKeys.filename.rawValue)
        coder.encode(currentPageNumber, forKey: StateRestorationKeys.pageNumber.rawValue)
    }
    
    override func decodeRestorableState(with coder: NSCoder) {
        guard let savedFilename = coder.decodeObject(forKey: StateRestorationKeys.filename.rawValue) as? String, savedFilename == pdfName
            else { return }
        logMilestone()

        let savedPageNumber = coder.decodeInteger(forKey: StateRestorationKeys.pageNumber.rawValue)
        if usePageSynchronizer {
            pageSynchronizer = PDFPageSynchronizer(with: self, pageNumber: savedPageNumber)
        }
        pdfView.go(to: savedPageNumber)
    }
}

// MARK: - PDFPageSynchronizerDelegate
extension ViewController: PDFPageSynchronizerDelegate {
    func pdfPageSynchronizer(_: PDFPageSynchronizer, didReceivePage page: Int) {
        DispatchQueue.main.async {
            self.pdfView.go(to: page)
        }
    }
    
    var pdfDocumentPageCount: Int {
        return pdfDocument.pageCount
    }

    func pdfPageSynchronizerPeersUpdated(_: PDFPageSynchronizer) -> Void {
        disconnectButton.isEnabled = pageSynchronizer?.peerCount != 0
    }

}
