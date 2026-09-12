import SwiftUI

struct ProjectLibraryFiltersView: View {
    @Binding var filters: ProjectLibraryFilters

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Filter projects").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Reset") { filters = .init(sort: filters.sort) }
                    .blitzButton(.quiet)
                    .controlSize(.small)
                    .disabled(filters.activeCount == 0)
            }
            BlitzFormDropdown(configuration: .init(
                title: "Recorded", selection: $filters.recorded,
                options: ProjectLibraryFilters.Recorded.allCases.map { .init(value: $0, title: $0.rawValue, detail: nil) }
            ))
            BlitzFormDropdown(configuration: .init(
                title: "Duration", selection: $filters.duration,
                options: ProjectLibraryFilters.Duration.allCases.map { .init(value: $0, title: $0.rawValue, detail: nil) }
            ))
            BlitzFormDropdown(configuration: .init(
                title: "Quality", selection: $filters.quality,
                options: ProjectLibraryFilters.Quality.allCases.map { .init(value: $0, title: $0.rawValue, detail: nil) }
            ))
            BlitzFormDropdown(configuration: .init(
                title: "Source", selection: $filters.source,
                options: ProjectLibraryFilters.Source.allCases.map { .init(value: $0, title: $0.rawValue, detail: nil) }
            ))
            BlitzFormDropdown(configuration: .init(
                title: "Transcript", selection: $filters.transcript,
                options: ProjectLibraryFilters.Transcript.allCases.map { .init(value: $0, title: $0.rawValue, detail: nil) }
            ))
        }
        .padding(16)
        .frame(width: 390)
        .background(BlitzUI.panelBackground)
    }
}
