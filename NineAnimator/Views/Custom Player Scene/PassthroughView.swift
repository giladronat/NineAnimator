//
//  PassthroughView.swift
//  NineAnimator
//
//  Created by Gilad Ronat on 8/11/19.
//  Copyright © 2019 Marcus Zhou. All rights reserved.
//

import UIKit

class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view == self ? nil : view
    }
}
