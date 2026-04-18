//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import AttributionsUI
import Sparkle

@main
struct MacApp: App {

    // swiftlint:disable:next weak_delegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        MainWindow(updater: updaterController.updater)
        MenuBarWindow()
        SettingsWindow()
        AboutWindow(developedBy: "Apparata AB",
                    attributionsWindowID: AttributionsWindow.windowID)
        AttributionsWindow([
            ("Sparkle", .mit(year: "2006-2017", holder: "Andy Matuschak et al."))
        ], header: "The following software may be included in this product.")
        HelpWindow()
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
