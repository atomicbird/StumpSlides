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
    var pdfDocument: PDFDocument!
    var pdfView: PDFView!
    var pdfThumbnailView: PDFThumbnailView!
    var pdfThumbnailScrollView: UIScrollView!
    var thumbnailContainerView: UIView!

    var stumpmojiWatcher: StumpmojiWatcher!
    var stumpMojis: StumpmojiView!

    var backgroundColortimer: Timer!

    let useThumbnailScrollView = true

    let thumbnailSize: Int = 150
    // Without some extra padding, PDFThumbnailView has geometry trouble with PDFs more than around 20 pages long when the scroll view is used. Tapping on a thumbnail may bring up an adjacent page instead of the tapped page, and the enlarged "selected" view of the thumbnail will be off center. This was reported in FB7379442, 2019-10-15.
    // Adding a little horizontal padding gets normal behavior on iOS 13.1 but this is not documented and is something I found by experimenting.
    let pdfThumbnailPerPagePadding = 2
    
    var pageSynchronizer: PDFPageSynchronizer!
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Load PDF
        if let documentURL = Bundle.main.url(forResource: pdfName, withExtension: nil),
            let pdfDocument = PDFDocument(url: documentURL) {
            self.pdfDocument = pdfDocument
        } else {
            print("Couldn't load file \(pdfName)")
        }
        
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
        
        if useThumbnailScrollView {
            pdfThumbnailView.frame = CGRect(x: 0, y: 0, width: thumbnailSize*(pdfDocument.pageCount + pdfThumbnailPerPagePadding), height: thumbnailSize)
            NSLayoutConstraint.activate([
                pdfThumbnailView.heightAnchor.constraint(equalToConstant: CGFloat(thumbnailSize)),
                pdfThumbnailView.widthAnchor.constraint(equalToConstant: CGFloat(thumbnailSize*(pdfDocument.pageCount + pdfThumbnailPerPagePadding)))
            ])
            // Add a scroll view to hold the thumbnail view
            pdfThumbnailScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: thumbnailSize*pdfDocument.pageCount, height: thumbnailSize))
            pdfThumbnailScrollView.translatesAutoresizingMaskIntoConstraints = false
            pdfThumbnailScrollView.backgroundColor = .clear
            pdfThumbnailScrollView.addSubview(pdfThumbnailView)
            pdfThumbnailView.backgroundColor = .clear
            pdfThumbnailScrollView.indicatorStyle = .white
            pdfThumbnailScrollView.alpha = 0
            
            NSLayoutConstraint.activate([
                pdfThumbnailView.leadingAnchor.constraint(equalTo: pdfThumbnailScrollView.leadingAnchor),
                pdfThumbnailView.trailingAnchor.constraint(equalTo: pdfThumbnailScrollView.trailingAnchor),
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
            
            pdfThumbnailView.backgroundColor = .clear
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
        stumpmojiWatcher.startWatching()
        
        pageSynchronizer = PDFPageSynchronizer(with: self)

        // This notification is posted
        // - When the PDFView's "document" property is set. The page is page 0.
        // - When state restoration happens.
        // - When the user moves to a new page.
        NotificationCenter.default.addObserver(forName: NSNotification.Name.PDFViewPageChanged, object: nil, queue: OperationQueue.main) { [weak self] (notification) in
            logMilestone("Page change notification")
            guard let self = self else { return }
            logMilestone("PDF page change: \(notification)")
            logMilestone("Current page: \(String(describing: self.pdfView.currentPage))")
            logMilestone("Visible pages: \(self.pdfView.visiblePages)")
            if let currentPage = self.pdfView.currentPage {
                let pageIndex = self.pdfDocument.index(for: currentPage)
                logMilestone("Sending page index: \(pageIndex)")
                self.pageSynchronizer.send(pageNumber: pageIndex)
            }
        }
        pdfView.document = pdfDocument
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pageSynchronizer.startSyncing()
        logMilestone()
    }

    override var prefersStatusBarHidden: Bool { return true }

    @objc func pdfViewTapped() -> Void {
        let newAlpha: CGFloat = {
            if thumbnailContainerView.alpha < 0.5 {
                return 1.0
            } else {
                return 0.0
            }
        }()
        UIView.animate(withDuration: 0.3) {
            self.thumbnailContainerView.alpha = newAlpha
        }
    }
    
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
        logMilestone()
        guard let savedFilename = coder.decodeObject(forKey: StateRestorationKeys.filename.rawValue) as? String
            else { return }
        let savedPageNumber = coder.decodeInteger(forKey: StateRestorationKeys.pageNumber.rawValue)
        
        if savedFilename == pdfName {
            pdfView.go(to: savedPageNumber)
        }
    }
}

extension UIView {
    func addSubviewAndConstrain(_ subview: UIView) -> Void {
        subview.frame = self.bounds
        subview.translatesAutoresizingMaskIntoConstraints = false
        
        subview.alpha = 1.0
        self.addSubview(subview)
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalTo: subview.widthAnchor, multiplier: 1.0),
            self.heightAnchor.constraint(equalTo: subview.heightAnchor, multiplier: 1.0),
            self.leadingAnchor.constraint(equalTo: subview.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: subview.trailingAnchor),
            self.topAnchor.constraint(equalTo: subview.topAnchor),
            self.bottomAnchor.constraint(equalTo: subview.bottomAnchor)
            ])
    }
}

extension ViewController: PDFPageSynchronizerDelegate {
    func pdfPageSynchronizer(_: PDFPageSynchronizer, didReceivePage page: Int) {
        DispatchQueue.main.async {
            self.pdfView.go(to: page)
        }
    }
}
