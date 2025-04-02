//
//  Copyright © 2025 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox

struct MenuBarPopup: View {
    
    @Environment(\.openWindow) var openWindow
        
    var body: some View {
        VStack(spacing: 20) {
            Text("Hello, World!")
            Button {
                openWindow(id: AboutWindow.windowID)
            } label: {
                Text("About...")
            }
        }
        .frame(width: 200, height: 200)
    }
}

struct MenuBarPopup_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarPopup()
    }
}
