/// Reusable row of headline numbers ("2 Present · 0 Absent · 2 Total").
import SwiftUI

/// One number-over-label stat in a `StatStrip`.
struct StatStripItem: Identifiable {
    let value: String
    let label: String
    let color: Color
    var valueFont: Font = .title2

    var id: String { label }
}

/// Lays stats out in one evenly spaced row, falling back to a two-column grid, then a
/// single column, when they don't fit — at accessibility text sizes a single row forced labels
/// like "Present" to hyphenate mid-word.
struct StatStrip: View {
    let items: [StatStripItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items) { tile($0).frame(maxWidth: .infinity) }
            }
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                    GridRow(alignment: .top) {
                        ForEach(items[start..<min(start + 2, items.count)]) { tile($0) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            // A value like "Oct 2026" can overflow even two columns at the largest sizes.
            VStack(spacing: 12) {
                ForEach(items) { tile($0) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func tile(_ item: StatStripItem) -> some View {
        VStack(spacing: 4) {
            Text(item.value).font(item.valueFont).fontWeight(.bold).foregroundStyle(item.color)
            Text(item.label).font(.caption).foregroundStyle(Color.readableSecondary)
        }
        // Never break a label mid-word; the grid fallback gives it room instead.
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
