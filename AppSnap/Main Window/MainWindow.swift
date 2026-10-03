//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import Sparkle

struct MainWindow: Scene {

    let updater: SPUUpdater

    var body: some Scene {

        WindowGroup {
            ContentView()
                .frame(minWidth: ContentView.minimumSize.width, minHeight: ContentView.minimumSize.height)
        }
        .defaultSize(width: 400, height: 700)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            AboutCommand()
            CheckForUpdatesCommand(updater: updater)

            // Remove the "New Window" option from the File menu.
            CommandGroup(replacing: .newItem, addition: { })
        }

    }
}
