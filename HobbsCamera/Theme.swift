// Theme.swift
import SwiftUI

/// Shared colors and building blocks for the app's dark, instrument-panel look.
enum Theme {
    static let background = Color.black
    static let card = Color(white: 0.10)
    static let cardStroke = Color.white.opacity(0.07)
    static let live = Color(red: 0.30, green: 0.85, blue: 0.47)
    static let caution = Color(red: 1.0, green: 0.70, blue: 0.22)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.36)
}

// MARK: - Location status styling

extension LocationStatus? {
    /// Icon, color and short label for a photo's location status. `nil` is a photo from before location was recorded.
    var style: (icon: String, color: Color, label: String) {
        switch self {
        case .live:
            return ("location.fill", Theme.live, "Location recorded")
        case .lastKnown:
            return ("location", Theme.caution, "Last known location")
        case .unavailable:
            return ("location.slash.fill", Theme.caution, "No GPS fix")
        case .denied:
            return ("location.slash.fill", Theme.caution, "Location off")
        case nil:
            return ("location.slash", .secondary, "No location recorded")
        }
    }
}

// MARK: - Modifiers

extension View {
    /// Frosted capsule used for floating controls.
    func glassCapsule() -> some View {
        background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    /// Rounded card used for grouped content.
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 0.5)
            )
    }
}

// MARK: - Components

/// Small uppercase label above a group of content.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

/// A colored capsule describing a status.
struct StatusChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// The round shutter button, used on the camera and to open it from the library.
struct ShutterButton: View {
    var isBusy: Bool = false
    var size: CGFloat = 76
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: size, height: size)

                Circle()
                    .fill(.white)
                    .frame(width: size - 14, height: size - 14)
                    .scaleEffect(isBusy ? 0.82 : 1)
                    .opacity(isBusy ? 0.7 : 1)

                if isBusy {
                    ProgressView()
                        .tint(.black)
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
            .animation(.spring(duration: 0.25), value: isBusy)
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

/// Shrinks slightly while pressed.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
