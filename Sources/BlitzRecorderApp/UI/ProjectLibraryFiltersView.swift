import SwiftUI

/// Sort and filters as one compact panel: every choice visible as a segment, no nested dropdowns.
struct ProjectLibraryFiltersView: View {
    @Binding var filters: ProjectLibraryFilters

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(.init(title: "Sort", picker: AnyView(BlitzSegmentedPicker(configuration: .init(
                title: "Sort", options: [.newest, .oldest, .longest, .title],
                selection: $filters.sort, label: { $0.shortTitle }
            )))))
            row(.init(title: "Recorded", picker: AnyView(segments(.init(
                title: "Recorded", selection: $filters.recorded, label: \.shortTitle)))))
            if filters.activeCount > 0 {
                Button("Clear filters") { filters = .init(sort: filters.sort) }
                    .blitzButton(.quiet)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(BlitzUI.panelBackground)
        .controlSize(.mini)
    }

    private struct Row {
        let title: String
        let picker: AnyView
    }

    private func row(_ row: Row) -> some View {
        HStack(spacing: 10) {
            Text(row.title)
                .font(BlitzType.label)
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 72, alignment: .leading)
            row.picker
        }
    }

    private struct Segments<Value: Hashable & CaseIterable> where Value.AllCases == [Value] {
        let title: String
        let selection: Binding<Value>
        let label: KeyPath<Value, String>
    }

    private func segments<Value: Hashable & CaseIterable>(_ segments: Segments<Value>) -> some View
    where Value.AllCases == [Value] {
        BlitzSegmentedPicker(configuration: .init(
            title: segments.title,
            options: Value.allCases,
            selection: segments.selection,
            label: { $0[keyPath: segments.label] }
        ))
    }
}

extension ProjectLibraryFilters.Sort {
    var shortTitle: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .longest: "Longest"
        case .shortest: "Shortest"
        case .title: "A–Z"
        }
    }
}

extension ProjectLibraryFilters.Recorded {
    var shortTitle: String {
        switch self {
        case .any: "Any"
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        }
    }
}
