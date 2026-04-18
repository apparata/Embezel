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
                .frame(minWidth: 400, minHeight: 700)
        }
        .defaultSize(width: 400, height: 700)
        .commands {
            AboutCommand()
            CheckForUpdatesCommand(updater: updater)
            HelpCommands()

            /// Add a menu with custom commands
            MyCommands()

            // Remove the "New Window" option from the File menu.
            CommandGroup(replacing: .newItem, addition: { })
        }

    }
}
