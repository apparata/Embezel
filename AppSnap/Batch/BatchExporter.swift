//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// Exports a batch's framed files to a folder. Existing files are never
/// overwritten; a " 2" suffix is added instead.
enum BatchExporter {

    struct Summary {
        var exported = 0
        var skipped = 0
        var failed = 0

        var message: String {
            var parts = ["Exported \(exported)"]
            if skipped > 0 {
                parts.append("skipped \(skipped)")
            }
            if failed > 0 {
                parts.append("\(failed) failed")
            }
            return parts.joined(separator: ", ")
        }
    }

    /// Exports the given files and reports progress as (done, total).
    /// Items that aren't ready count as skipped. Cancelling the calling task
    /// stops after the current file.
    @MainActor static func export(
        _ files: [PromisedFile],
        skipped: Int,
        to folder: URL,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> Summary {
        var summary = Summary(skipped: skipped)
        var taken = BatchPlanning.existingFileNames(in: folder)
        progress(0, files.count)

        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let name = (file.fileName as NSString).deletingPathExtension
            let fileExtension = (file.fileName as NSString).pathExtension
            let url = folder.appendingPathComponent(
                BatchPlanning.uniqueFileName(name, extension: fileExtension, taken: &taken)
            )
            do {
                try await file.write(url)
                summary.exported += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                print("Could not export \(url.lastPathComponent): \(error)")
                summary.failed += 1
            }
            progress(index + 1, files.count)
        }
        return summary
    }
}
