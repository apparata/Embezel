//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox

struct MainWindow: Scene {
    
    var body: some Scene {

        WindowGroup {
            ContentView()
                .frame(minWidth: 400, minHeight: 700)
        }
        .defaultSize(width: 400, height: 700)
        .commands {
            AboutCommand()
            HelpCommands()
            
            /// Add a menu with custom commands
            MyCommands()
            
            // Remove the "New Window" option from the File menu.
            CommandGroup(replacing: .newItem, addition: { })
        }
        
    }
}
