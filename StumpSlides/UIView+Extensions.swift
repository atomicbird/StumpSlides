//
//  UIView+Extensions.swift
//  StumpSlides
//
//  Created by Tom Harrington on 10/24/19.
//  Copyright © 2019 Atomic Bird LLC. All rights reserved.
//

import UIKit

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
