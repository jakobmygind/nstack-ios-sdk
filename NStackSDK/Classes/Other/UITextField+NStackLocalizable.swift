//
//  UITextField+NStackLocalizable.swift
//  NStackSDK
//
//  Created by Nicolai Harbo on 30/07/2019.
//  Copyright © 2019 Nodes ApS. All rights reserved.
//

import Foundation

#if canImport(UIKit)
import UIKit

extension UITextField: NStackLocalizable {

    private static var _backgroundColor = [String: UIColor?]()
    private static var _userInteractionEnabled = [String: Bool]()
    private static var _localizationItemIdentifier = [String: LocalizationItemIdentifier]()

    @objc public func localize(for stringIdentifier: String) {
        guard let identifier = SectionKeyHelper.transform(stringIdentifier) else { return }
        NStack.sharedInstance.localizationManager?.localize(component: self, for: identifier)
    }

    @objc public func setLocalizedValue(_ localizedValue: String) {
        text = localizedValue
    }

    public var localizableValue: String? {
        get {
            return text
        }
        set {
            text = newValue
        }
    }

    public var localizationItemIdentifier: LocalizationItemIdentifier? {
        get {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            return UITextField._localizationItemIdentifier[tmpAddress]
        }
        set {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            UITextField._localizationItemIdentifier[tmpAddress] = newValue
        }
    }

    public var originalBackgroundColor: UIColor? {
        get {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            return UITextField._backgroundColor[tmpAddress] ?? .clear
        }
        set {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            UITextField._backgroundColor[tmpAddress] = newValue
        }
    }

    public var originalIsUserInteractionEnabled: Bool {
        get {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            return UITextField._userInteractionEnabled[tmpAddress] ?? false
        }
        set {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            UITextField._userInteractionEnabled[tmpAddress] = newValue
        }
    }

    public var backgroundViewToColor: UIView? {
        return self
    }

}
#endif
