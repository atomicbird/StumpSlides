//
//  PDFView+Extensions.swift
//  StumpSlides
//
//  Created by Tom Harrington on 10/16/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import PDFKit

extension PDFView {
    /// Go to the page at the requested index in the current document. If there is no current document or if there's no such page index in the document, do nothing.
    /// - Parameter pageIndex: Index of the page to display
    func go(to pageIndex: Int) -> Void {
        guard let newPage = self.document?.page(at: pageIndex) else { return }
        self.go(to: newPage)
    }
    
    /// Go to the next page in the current document. If the last page is visible, wrap around to the first page. If there's no current document, do nothing.
    func goToNextPage() -> Void {
        guard let currentPage = self.currentPage else { return }
        guard let document = document else { return }
        
        let currentPageIndex = document.index(for: currentPage)
        let pageCount = document.pageCount
        
        let newPageIndex = (currentPageIndex + 1) % pageCount
        go(to: newPageIndex)
    }
    
    var currentPageNumber: Int? {
        guard let currentPage = self.currentPage,
            let document = document
            else { return nil }
        return document.index(for: currentPage)
    }
    
}
