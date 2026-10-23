//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// The model + color picker, the pose control (only when several poses
/// fit) and the rotate button (landscape only).
struct BezelControls: View {

    let choices: BezelChoices
    let modelColor: ModelColor
    let pose: Pose?
    let poseOptions: [Pose]
    let showsRotate: Bool
    let onSelectModelColor: (ModelColor) -> Void
    let onSelectPose: (Pose) -> Void
    var onRotate: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Picker(modelColor.model, selection: Binding(
                get: { modelColor },
                set: { onSelectModelColor($0) }
            )) {
                ForEach(choices.models, id: \.self) { deviceModel in
                    Section(deviceModel) {
                        ForEach(choices.colors(for: deviceModel), id: \.self) { color in
                            Text(color)
                                .tag(ModelColor(model: deviceModel, color: color))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 260)

            HStack {
                if poseOptions.count > 1, let pose {
                    Picker("Pose", selection: Binding(
                        get: { pose },
                        set: { onSelectPose($0) }
                    )) {
                        ForEach(poseOptions, id: \.self) { pose in
                            Text(pose.shortName).tag(pose)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if showsRotate {
                    Button {
                        onRotate()
                    } label: {
                        Label("Rotate", systemImage: "rotate.right")
                    }
                    .help("Rotate 180° to put the Dynamic Island on the other side")
                }
            }
        }
    }
}

extension BezelControls {

    /// Controls for a single selection.
    init(
        choices: BezelChoices,
        selection: Selection,
        onSelectModelColor: @escaping (ModelColor) -> Void,
        onSelectPose: @escaping (Pose) -> Void,
        onRotate: @escaping () -> Void
    ) {
        let modelColor = ModelColor(model: selection.bezel.model, color: selection.bezel.color)
        self.init(
            choices: choices,
            modelColor: modelColor,
            pose: selection.bezel.pose,
            poseOptions: choices.poses(for: modelColor),
            showsRotate: selection.bezel.pose.isLandscape,
            onSelectModelColor: onSelectModelColor,
            onSelectPose: onSelectPose,
            onRotate: onRotate
        )
    }
}
