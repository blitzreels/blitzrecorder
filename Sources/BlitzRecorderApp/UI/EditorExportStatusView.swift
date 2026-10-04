import SwiftUI

enum EditorExportStatus {
    struct Progress {
        let title: String
        let percentage: String
        let detail: String?
        let value: Double?

        var supplementaryDetail: String? {
            guard let detail else { return nil }
            let ignored = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
            let normalizedTitle = title.trimmingCharacters(in: ignored)
            let normalizedDetail = detail.trimmingCharacters(in: ignored)
            guard !normalizedDetail.isEmpty,
                  normalizedDetail.localizedCaseInsensitiveCompare(normalizedTitle) != .orderedSame else {
                return nil
            }
            return detail
        }
    }

    case exporting(Progress)
    case succeeded(URL)
    case failed(String)
}

enum EditorExportFollowUp: Equatable {
    case share(URL)
    case sendToBlitzReels(URL)
}

extension View {
    func editorNoticeSurface() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: 720)
            .background(.regularMaterial, in: .rect(cornerRadius: BlitzUI.cardRadius))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .environment(\.colorScheme, .dark)
    }
}
