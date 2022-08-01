//
//  UIView+Extensions.swift
//  StumpSlides
//
//  Created by Tom Harrington on 10/24/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import UIKit

extension UIView {
    func addSubviewAndConstrain(_ subview: UIView, inset: UIEdgeInsets = UIEdgeInsets.zero) -> Void {
        subview.frame = self.bounds.inset(by: inset)
        subview.translatesAutoresizingMaskIntoConstraints = false
        
        subview.alpha = 1.0
        self.addSubview(subview)
        
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: subview.leadingAnchor, constant: inset.left),
            self.trailingAnchor.constraint(equalTo: subview.trailingAnchor, constant: inset.right),
            self.topAnchor.constraint(equalTo: subview.topAnchor, constant: inset.top),
            self.bottomAnchor.constraint(equalTo: subview.bottomAnchor, constant: inset.bottom)
            ])
    }
}
