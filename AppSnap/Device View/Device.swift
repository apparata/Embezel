//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import AppKit

struct Device {
    let name: String
    let images: [String: NSImage]
    let mask: NSImage
    let maskOffset: CGSize
    let screenSize: CGSize

    var variants: [String] {
        images.keys.map { String($0) }.sorted()
    }
}

extension Device {

    static let iPhone16Pro = Device(
        name: "iPhone 16 Pro",
        images: [
            "Black Titanium": .Device.IPhone16Pro.blackTitanium,
            "Desert Titanium": .Device.IPhone16Pro.desertTitanium,
            "Natural Titanium": .Device.IPhone16Pro.naturalTitanium,
            "White Titanium": .Device.IPhone16Pro.whiteTitanium
        ],
        mask: .Device.IPhone16Pro.mask,
        maskOffset: CGSize(width: 72, height: 69),
        screenSize: CGSize(width: 1206, height: 2622)
    )

    static let iPhone16ProMax = Device(
        name: "iPhone 16 Pro Max",
        images: [
            "Black Titanium": .Device.IPhone16ProMax.blackTitanium,
            "Desert Titanium": .Device.IPhone16ProMax.desertTitanium,
            "Natural Titanium": .Device.IPhone16ProMax.naturalTitanium,
            "White Titanium": .Device.IPhone16ProMax.whiteTitanium
        ],
        mask: .Device.IPhone16ProMax.mask,
        maskOffset: CGSize(width: 75, height: 66),
        screenSize: CGSize(width: 1320, height: 2868)
    )
}
