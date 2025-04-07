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

    static let all: [Device] = [
        iPhone16, iPhone16Plus, iPhone16Pro, iPhone16ProMax,
        iPhone15, iPhone15Plus, iPhone15Pro, iPhone15ProMax,
        iPhone14, iPhone14Plus, iPhone14Pro, iPhone14ProMax
    ]

    // MARK: - iPhone 14

    static let iPhone14 = Device(
        name: "iPhone 14",
        images: [
            "Blue": .Device.IPhone14.blue,
            "Midnight": .Device.IPhone14.midnight,
            "Purple": .Device.IPhone14.purple,
            "Red": .Device.IPhone14.red,
            "Starlight": .Device.IPhone14.starlight
        ],
        mask: .Device.IPhone14.mask,
        maskOffset: CGSize(width: 100, height: 100),
        screenSize: CGSize(width: 1170, height: 2532)
    )

    // MARK: - iPhone 14 Plus

    static let iPhone14Plus = Device(
        name: "iPhone 14 Plus",
        images: [
            "Blue": .Device.IPhone14Plus.blue,
            "Midnight": .Device.IPhone14Plus.midnight,
            "Purple": .Device.IPhone14Plus.purple,
            "Red": .Device.IPhone14Plus.red,
            "Starlight": .Device.IPhone14Plus.starlight
        ],
        mask: .Device.IPhone14Plus.mask,
        maskOffset: CGSize(width: 90, height: 100),
        screenSize: CGSize(width: 1284, height: 2778)
    )

    // MARK: - iPhone 14 Pro

    static let iPhone14Pro = Device(
        name: "iPhone 14 Pro",
        images: [
            "Deep Purple": .Device.IPhone14Pro.deepPurple,
            "Gold": .Device.IPhone14Pro.gold,
            "Silver": .Device.IPhone14Pro.silver,
            "Space Black": .Device.IPhone14Pro.spaceBlack
        ],
        mask: .Device.IPhone14Pro.mask,
        maskOffset: CGSize(width: 80, height: 80),
        screenSize: CGSize(width: 1179, height: 2556)
    )

    // MARK: - iPhone 14 Pro Max

    static let iPhone14ProMax = Device(
        name: "iPhone 14 Pro Max",
        images: [
            "Deep Purple": .Device.IPhone14ProMax.deepPurple,
            "Gold": .Device.IPhone14ProMax.gold,
            "Silver": .Device.IPhone14ProMax.silver,
            "Space Black": .Device.IPhone14ProMax.spaceBlack
        ],
        mask: .Device.IPhone14ProMax.mask,
        maskOffset: CGSize(width: 80, height: 70),
        screenSize: CGSize(width: 1290, height: 2796)
    )

    // MARK: - iPhone 15

    static let iPhone15 = Device(
        name: "iPhone 15",
        images: [
            "Black": .Device.IPhone15.black,
            "Blue": .Device.IPhone15.blue,
            "Green": .Device.IPhone15.green,
            "Pink": .Device.IPhone15.pink,
            "Yellow": .Device.IPhone15.yellow
        ],
        mask: .Device.IPhone15.mask,
        maskOffset: CGSize(width: 120, height: 120),
        screenSize: CGSize(width: 1179, height: 2556)
    )

    // MARK: - iPhone 15 Plus

    static let iPhone15Plus = Device(
        name: "iPhone 15 Plus",
        images: [
            "Black": .Device.IPhone15Plus.black,
            "Blue": .Device.IPhone15Plus.blue,
            "Green": .Device.IPhone15Plus.green,
            "Pink": .Device.IPhone15Plus.pink,
            "Yellow": .Device.IPhone15Plus.yellow
        ],
        mask: .Device.IPhone15Plus.mask,
        maskOffset: CGSize(width: 120, height: 120),
        screenSize: CGSize(width: 1290, height: 2796)
    )

    // MARK: - iPhone 15 Pro

    static let iPhone15Pro = Device(
        name: "iPhone 15 Pro",
        images: [
            "Black Titanium": .Device.IPhone15Pro.blackTitanium,
            "Blue Titanium": .Device.IPhone15Pro.blueTitanium,
            "Natural Titanium": .Device.IPhone15Pro.naturalTitanium,
            "White Titanium": .Device.IPhone15Pro.whiteTitanium
        ],
        mask: .Device.IPhone15Pro.mask,
        maskOffset: CGSize(width: 120, height: 120),
        screenSize: CGSize(width: 1179, height: 2556)
    )

    // MARK: - iPhone 15 Pro Max

    static let iPhone15ProMax = Device(
        name: "iPhone 15 Pro Max",
        images: [
            "Black Titanium": .Device.IPhone15ProMax.blackTitanium,
            "Blue Titanium": .Device.IPhone15ProMax.blueTitanium,
            "Natural Titanium": .Device.IPhone15ProMax.naturalTitanium,
            "White Titanium": .Device.IPhone15ProMax.whiteTitanium
        ],
        mask: .Device.IPhone15ProMax.mask,
        maskOffset: CGSize(width: 120, height: 120),
        screenSize: CGSize(width: 1290, height: 2796)
    )

    // MARK: - iPhone 16

    static let iPhone16 = Device(
        name: "iPhone 16",
        images: [
            "Black": .Device.IPhone16.black,
            "Pink": .Device.IPhone16.pink,
            "Teal": .Device.IPhone16.teal,
            "Ultramarine": .Device.IPhone16.ultramarine,
            "White": .Device.IPhone16.white
        ],
        mask: .Device.IPhone16.mask,
        maskOffset: CGSize(width: 90, height: 90),
        screenSize: CGSize(width: 1179, height: 2556)
    )

    // MARK: - iPhone 16 Plus

    static let iPhone16Plus = Device(
        name: "iPhone 16 Plus",
        images: [
            "Black": .Device.IPhone16Plus.black,
            "Pink": .Device.IPhone16Plus.pink,
            "Teal": .Device.IPhone16Plus.teal,
            "Ultramarine": .Device.IPhone16Plus.ultramarine,
            "White": .Device.IPhone16Plus.white
        ],
        mask: .Device.IPhone16Plus.mask,
        maskOffset: CGSize(width: 90, height: 87),
        screenSize: CGSize(width: 1290, height: 2796)
    )

    // MARK: - iPhone 16 Pro

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

    // MARK: - iPhone 16 Pro Max

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
