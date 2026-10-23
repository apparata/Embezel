//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import AppKit

/// The batch grid: one section per device group with the group's picker,
/// then the items that couldn't be framed.
struct BatchView: View {

    @Bindable var batch: BatchModel

    /// Where a shift-click range starts.
    @State private var anchorID: BatchModel.Item.ID?

    @State private var customizingID: BatchModel.Item.ID?

    /// The items shown large over the grid: one, or a multiple selection.
    @State private var previewIDs: [BatchModel.Item.ID] = []

    /// The previewed item, or the one centered in a strip of several.
    @State private var previewID: BatchModel.Item.ID?

    @FocusState private var isFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                ForEach(batch.groups) { group in
                    groupSection(group)
                }

                if !batch.loadingItems.isEmpty || !batch.unsupportedItems.isEmpty {
                    otherSection
                }
            }
            .padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            batch.selectedIDs = []
            isFocused = true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onCommand(#selector(NSResponder.selectAll(_:))) {
            batch.selectedIDs = Set(batch.items.map(\.id))
        }
        .onDeleteCommand {
            batch.remove(batch.selectedIDs)
        }
        .onCopyCommand {
            batch.readyItems(batch.selectedIDs).compactMap { item in
                item.renderedURL.flatMap { NSItemProvider(contentsOf: $0) }
            }
        }
        .onKeyPress(.space) {
            guard let id = displayOrder.first(where: { batch.selectedIDs.contains($0) }) else {
                return .ignored
            }
            preview(id)
            return .handled
        }
        .overlay {
            if let previewID {
                BatchPreview(
                    batch: batch,
                    ids: previewIDs,
                    currentID: Binding(
                        get: { previewID },
                        set: { self.previewID = $0 }
                    ),
                    onClose: closePreview,
                    onMove: movePreview
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Preview

    /// Items that can be previewed, in the order they are shown.
    private var previewableIDs: [BatchModel.Item.ID] {
        displayOrder.filter { id in
            batch.item(id).map { $0.isReady || $0.thumbnail != nil } == true
        }
    }

    /// Previews the item, or the whole selection if the item is part of a
    /// multiple selection.
    private func preview(_ id: BatchModel.Item.ID) {
        let previewable = previewableIDs
        let ids = previewable.filter { targets(for: id).contains($0) }
        guard !ids.isEmpty else {
            return
        }
        if ids.count == 1 {
            batch.selectedIDs = [ids[0]]
            anchorID = ids[0]
        }
        withAnimation(.smooth(duration: 0.2)) {
            previewIDs = ids
            previewID = ids.contains(id) ? id : ids[0]
        }
    }

    private func closePreview() {
        withAnimation(.smooth(duration: 0.2)) {
            previewID = nil
            previewIDs = []
        }
        isFocused = true
    }

    /// Shows the previous or next previewable item, and selects it, like
    /// Quick Look in Finder.
    private func movePreview(_ offset: Int) {
        let ids = previewableIDs
        guard let previewID, let index = ids.firstIndex(of: previewID), !ids.isEmpty else {
            return
        }
        let next = ids[(index + offset + ids.count) % ids.count]
        self.previewID = next
        previewIDs = [next]
        batch.selectedIDs = [next]
        anchorID = next
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(itemCountText)
                    .font(.title3.weight(.semibold))
                Text("Drag tiles out, or select some and drag them together. Recordings are encoded after the drop.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if batch.containsVideos {
                videoBackgroundControls
            }
            dragAllHandle
        }
    }

    /// Background of all recordings in the batch.
    private var videoBackgroundControls: some View {
        HStack {
            Picker("Recording Background", selection: Binding(
                get: { batch.videoBackground.isTransparent },
                set: { isTransparent in
                    batch.setVideoBackground(isTransparent ? .transparent : .color(batch.videoBackgroundColor))
                }
            )) {
                Text("Transparent").tag(true)
                Text("Color").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if !batch.videoBackground.isTransparent {
                ColorPicker("Background Color", selection: Binding(
                    get: { batch.videoBackgroundColor },
                    set: { batch.setVideoBackground(.color($0)) }
                ), supportsOpacity: false)
                .labelsHidden()
            }
        }
        .help("Background of exported recordings: transparent (.mov, HEVC with alpha) or a solid color (.mp4)")
    }

    private var itemCountText: String {
        let count = batch.items.count
        return count == 1 ? "1 file" : "\(count) files"
    }

    /// Drags every ready item.
    private var dragAllHandle: some View {
        Label("Drag All", systemImage: "square.on.square")
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                BatchDragSource(
                    files: { batch.dragFiles(for: Set(batch.items.map(\.id))) },
                    dragImageSize: CGSize(width: 120, height: 120)
                )
            }
            .opacity(batch.readyItems.isEmpty ? 0.5 : 1)
            .help("Drag all framed files")
    }

    // MARK: - Sections

    private func groupSection(_ group: BatchModel.Group) -> some View {
        let items = batch.items(in: group)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(batch.title(for: group))
                        .font(.headline)
                    Text(items.count == 1 ? "1 item" : "\(items.count) items")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                groupControls(group)
            }
            grid(items)
        }
    }

    private func groupControls(_ group: BatchModel.Group) -> some View {
        let poseOptions = batch.poseOptions(for: group)
        return BezelControls(
            choices: batch.choices(for: group),
            modelColor: group.modelColor,
            pose: group.pose ?? poseOptions.first,
            poseOptions: poseOptions,
            showsRotate: false,
            onSelectModelColor: { batch.setModelColor($0, for: group.id) },
            onSelectPose: { batch.setPose($0, for: group.id) }
        )
        .fixedSize()
    }

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Not Framed")
                .font(.headline)
            grid(batch.loadingItems + batch.unsupportedItems)
        }
    }

    private func grid(_ items: [BatchModel.Item]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { item in
                tile(item)
            }
        }
    }

    // MARK: - Tile

    private func tile(_ item: BatchModel.Item) -> some View {
        BatchTile(
            item: item,
            isSelected: batch.selectedIDs.contains(item.id),
            dragFiles: { batch.dragFiles(for: dragTargets(for: item.id)) },
            onClick: { click(item.id, modifiers: $0) },
            onDoubleClick: { preview(item.id) },
            onRotate: { batch.toggleRotation(targets(for: item.id)) }
        )
        .contextMenu {
            contextMenu(for: item)
        }
        .popover(isPresented: Binding(
            get: { customizingID == item.id },
            set: { if !$0 { customizingID = nil } }
        )) {
            customizePopover(item.id)
        }
    }

    @ViewBuilder private func contextMenu(for item: BatchModel.Item) -> some View {
        let targets = targets(for: item.id)
        let targetItems = batch.items.filter { targets.contains($0.id) }

        if item.isReady || item.thumbnail != nil {
            Button("Preview") {
                preview(item.id)
            }
        }
        if item.groupID != nil {
            Button("Customize…") {
                customizingID = item.id
            }
            if targetItems.contains(where: { $0.override != nil }) {
                Button("Use Group Setting") {
                    batch.useGroupSetting(targets)
                }
            }
            if targetItems.contains(where: { $0.selection?.bezel.pose.isLandscape == true }) {
                Button("Rotate 180°") {
                    batch.toggleRotation(targets)
                }
            }
            Divider()
        }
        let originals = targetItems.compactMap(\.originalURL)
        if !originals.isEmpty {
            Button("Show Original in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(originals)
            }
        }
        Button(targets.count == 1 ? "Remove from Batch" : "Remove \(targets.count) from Batch") {
            batch.remove(targets)
        }
    }

    @ViewBuilder private func customizePopover(_ id: BatchModel.Item.ID) -> some View {
        if let item = batch.item(id), let selection = batch.effectiveSelection(for: item) {
            VStack(spacing: 16) {
                Text(item.name)
                    .font(.headline)
                BezelControls(
                    choices: BezelChoices(candidates: item.candidates),
                    selection: selection,
                    onSelectModelColor: { batch.setModelColor($0, forItem: id) },
                    onSelectPose: { batch.setPose($0, forItem: id) },
                    onRotate: { batch.toggleRotation([id]) }
                )
                if item.override != nil {
                    Button("Use Group Setting") {
                        batch.useGroupSetting([id])
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Selection

    /// Actions on a selected item apply to the whole selection, like in
    /// Finder; on an unselected item, to that item only.
    private func targets(for id: BatchModel.Item.ID) -> Set<BatchModel.Item.ID> {
        batch.selectedIDs.contains(id) ? batch.selectedIDs : [id]
    }

    /// Dragging an unselected item drags only that item and doesn't change
    /// the selection.
    private func dragTargets(for id: BatchModel.Item.ID) -> Set<BatchModel.Item.ID> {
        targets(for: id)
    }

    private func click(_ id: BatchModel.Item.ID, modifiers: NSEvent.ModifierFlags) {
        isFocused = true
        if modifiers.contains(.command) {
            if batch.selectedIDs.contains(id) {
                batch.selectedIDs.remove(id)
            } else {
                batch.selectedIDs.insert(id)
            }
            anchorID = id
        } else if modifiers.contains(.shift), let anchorID,
                  let anchorIndex = displayOrder.firstIndex(of: anchorID),
                  let index = displayOrder.firstIndex(of: id) {
            let range = min(anchorIndex, index)...max(anchorIndex, index)
            batch.selectedIDs.formUnion(displayOrder[range])
        } else {
            batch.selectedIDs = [id]
            anchorID = id
        }
    }

    /// Items in the order they are shown: by group, then the rest.
    private var displayOrder: [BatchModel.Item.ID] {
        batch.groups.flatMap { batch.items(in: $0) }.map(\.id)
            + (batch.loadingItems + batch.unsupportedItems).map(\.id)
    }
}
