import SwiftUI

struct RemoveEffectView: View {

    @State var startDate = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let start = startDate
            VStack {
                Rectangle()
                    .foregroundColor(.red)
                    .visualEffect { content, proxy in
                        content
                            .colorEffect(removeEffect(
                                t: -start.timeIntervalSinceNow,
                                size: proxy.size
                            ))
                    }
            }
        }.overlay {
            Button {
                startDate = Date()
                print(startDate.timeIntervalSinceNow)
            } label: {
                Text("Push me!")
            }
        }
    }

    nonisolated
    private func removeEffect(t: Double, size: CGSize) -> Shader {
        ShaderLibrary.removeEffect(
            .float(t),
            .float2(size)
        )
    }
}

#Preview {
    RemoveEffectView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
}
