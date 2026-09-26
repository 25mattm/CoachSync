/// Dashboard weather card driven by `WeatherManager.Status`. iOS-only (WeatherKit entitlement +
/// location usage string exist only on the CoachSync iOS target, not CoachSyncMac) — this file
/// lives in the shared PBXFileSystemSynchronizedRootGroup that both targets compile, so it is
/// wrapped in `#if os(iOS)` in its entirety to compile to nothing on the Mac target.
#if os(iOS)

import SwiftUI
import UIKit

/// Renders one of `WeatherManager.Status`'s six states as a single card. `weather` is a plain
/// `let` — `WeatherManager` is `@Observable`, so SwiftUI still tracks `status` and re-renders
/// this view whenever it changes.
struct WeatherCardView: View {
    let weather: WeatherManager

    @State private var isExpanded = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch weather.status {
            case .idle:
                EmptyView()

            case .loading:
                loadingRow

            case let .loaded(conditions):
                loadedContent(conditions)

            case .denied:
                deniedRow

            case .unavailable:
                unavailableRow
            }
        }
        .padding(16)
        .background(
            Group {
                if #available(iOS 26, *) { Color.clear }
                else { RoundedRectangle(cornerRadius: 14).fill(.regularMaterial) }
            }
        )
        .ifAvailableiOS26 { $0.glassEffect(.regular, in: .rect(cornerRadius: 14)) }
    }

    // MARK: - .loading

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Fetching weather...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - .loaded

    @ViewBuilder
    private func loadedContent(_ conditions: CurrentConditions) -> some View {
        let stale = WeatherManager.isStale(fetchedAt: conditions.fetchedAt)

        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                loadedCompactRow(conditions)
            }
            .buttonStyle(.plain)

            if stale {
                Text("Updated " + conditions.fetchedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if isExpanded {
                loadedExpandedBlock(conditions, stale: stale)
            }

            weatherAttributionLink
        }
    }

    /// Required WeatherKit attribution. Must render whenever WeatherKit-sourced data is on
    /// screen — including the default collapsed card, which already shows temp/wind/UV/place —
    /// not just in the expanded detail block.
    private var weatherAttributionLink: some View {
        Link("Powered by Apple Weather", destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func loadedCompactRow(_ conditions: CurrentConditions) -> some View {
        HStack(spacing: 12) {
            Image(systemName: conditions.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("\(Int(conditions.temperatureC.rounded()))°C")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Label(
                        "\(Int(conditions.windSpeedKmh.rounded())) km/h \(conditions.windCompass)",
                        systemImage: "wind"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("UV \(conditions.uvIndex)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(conditions.placeName ?? "Current Location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .contentShape(Rectangle())
    }

    private func loadedExpandedBlock(_ conditions: CurrentConditions, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Feels like")
                        .foregroundStyle(.secondary)
                    Text("\(Int(conditions.feelsLikeC.rounded()))°C")
                }
                GridRow {
                    Text("Humidity")
                        .foregroundStyle(.secondary)
                    Text("\(Int(conditions.humidity * 100))%")
                }
                GridRow {
                    Text("Visibility")
                        .foregroundStyle(.secondary)
                    Text("\(Int(conditions.visibilityKm.rounded())) km")
                }
                GridRow {
                    Text("Dew point")
                        .foregroundStyle(.secondary)
                    Text("\(Int(conditions.dewPointC.rounded()))°C")
                }
            }
            .font(.caption)

            Text(conditions.conditionText)
                .font(.subheadline)

            // When stale, the orange relative-age label above the expanded block already
            // says when this reading is from — a second clock-time line would duplicate it.
            if !stale {
                Text("Updated " + conditions.fetchedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - .denied

    /// Stacked at accessibility text sizes — side by side, the message was squeezed to one word
    /// per line ("Loca-tion") next to the button.
    private var deniedRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Image(systemName: "location.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Location access needed for weather")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
            }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)   // stacked, the card would otherwise hug its text
    }

    // MARK: - .unavailable

    private var unavailableRow: some View {
        Button {
            Task { await weather.refresh() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cloud.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Weather unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#endif
