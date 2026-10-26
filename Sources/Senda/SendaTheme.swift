import AppKit
import SwiftUI

// Native adaptations of Beautiful UI Button and Task Rows.
// Source and license: THIRD_PARTY_NOTICES.md.
enum SendaTheme {
    static let accent = T.accent
    static let accentNS = T.accentNS
    static let surface = T.surface
    static let surfaceNS = T.surfaceNS
    static let canvas = T.canvas
    static let border = T.line
}

struct SendaIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(T.ink2)
            .frame(width: T.space(7), height: T.space(7))
            .background(RoundedRectangle(cornerRadius: T.radiusControl).fill(configuration.isPressed ? T.hover2 : T.inset))
            .contentShape(RoundedRectangle(cornerRadius: T.radiusControl))
            .opacity(enabled ? 1 : 0.5)
    }
}

struct SendaActionButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, T.space(3)).frame(height: T.space(7))
            .foregroundStyle(prominent ? T.canvas : T.ink)
            .background(Capsule().fill(prominent ? T.ink : (configuration.isPressed ? T.hover2 : T.surface)))
            .overlay(Capsule().strokeBorder(prominent ? T.ink : T.lineStrong))
            .opacity(enabled ? (configuration.isPressed ? 0.9 : 1) : 0.5)
            .contentShape(Capsule())
    }
}

struct SendaBadge: View {
    let title: String
    var foreground = T.ink2
    var background = T.hover
    var body: some View {
        Text(title).font(.system(size: 11, weight: .medium))
            .foregroundStyle(foreground).padding(.horizontal, T.space(2))
            .padding(.vertical, T.space(1)).background(Capsule().fill(background))
    }
}

struct SendaRule: View {
    var body: some View { Rectangle().fill(T.line).frame(height: T.space(0.25)) }
}

struct SendaProgressBar: View {
    let fraction: Double
    var color = T.accent
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(T.line).overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }.frame(height: T.space(1))
    }
}
