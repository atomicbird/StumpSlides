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
    
    let pdfName = "Stump 2019 Slides.pdf"
    var pdfDocument: PDFDocument!
    var pdfView: PDFView!
    var pdfThumbnailView: PDFThumbnailView!
    
    var stumpmojiWatcher: StumpmojiWatcher!
    var stumpMojis: StumpmojiView!

    var backgroundColortimer: Timer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add PDF view
        pdfView = PDFView(frame: view.bounds)
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.autoScales = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.backgroundColor = .black // This doesn't work-- see the ugly hack below
        view.addSubviewAndConstrain(pdfView)
        
        // Add thumbnails but hide them for now
        pdfThumbnailView = PDFThumbnailView()
        pdfThumbnailView.translatesAutoresizingMaskIntoConstraints = false
        pdfThumbnailView.pdfView = pdfView
        pdfThumbnailView.layoutMode = .horizontal
        pdfThumbnailView.thumbnailSize = CGSize(width: 150, height: 150)
        pdfThumbnailView.alpha = 0.0
        view.addSubview(pdfThumbnailView)
        NSLayoutConstraint.activate([
            pdfThumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfThumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfThumbnailView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfThumbnailView.heightAnchor.constraint(equalToConstant: 150)
            ])
        
        // Add tap gesture to show/hide thumbnails
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(pdfViewTapped))
        pdfView.addGestureRecognizer(tapGestureRecognizer)
        
        // Load PDF
        if let documentURL = Bundle.main.url(forResource: pdfName, withExtension: nil),
            let pdfDocument = PDFDocument(url: documentURL) {
            self.pdfDocument = pdfDocument
        } else {
            print("Couldn't load file \(pdfName)")
        }
        
        // Add overlay to show incoming messages
        stumpMojis = StumpmojiView(frame: view.bounds)
        view.addSubviewAndConstrain(stumpMojis)

        // Set up message listener
        stumpmojiWatcher = StumpmojiWatcher()
        stumpmojiWatcher.stumpmojiReceived = { (message) in
            self.stumpMojis.addMessage(message)
        }
        stumpmojiWatcher.startWatching()
        
        // Ugly hack to work around a bug where you can't set the background color of a PDFView if you're using it with a page view controller.
        backgroundColortimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] (timer) in
            guard let self = self else {
                timer.invalidate()
                return
            }
            var views = self.pdfView.subviews
            while let view = views.first {
                // Somewhere there's a _UIPageViewControllerContentView with a background that's 50% gray. Bastard.
                if NSStringFromClass(type(of:view)) == "_UIPageViewControllerContentView" {
                    UIView.animate(withDuration: 0.3, animations: {
                        view.backgroundColor = .black
                        self.backgroundColortimer.invalidate()
                    })
                }
                views.append(contentsOf: view.subviews)
                views.removeFirst()
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pdfView.document = pdfDocument
    }

    override var prefersStatusBarHidden: Bool { return true }

    @objc func pdfViewTapped() -> Void {
        let newAlpha: CGFloat = {
            if pdfThumbnailView.alpha < 0.5 {
                return 1.0
            } else {
                return 0.0
            }
        }()
        UIView.animate(withDuration: 0.3) {
            self.pdfThumbnailView.alpha = newAlpha
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
