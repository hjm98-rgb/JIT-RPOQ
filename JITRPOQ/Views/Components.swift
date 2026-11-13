//
//  Components.swift
//  JIT RPOQ
//

import SwiftUI

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StatusPill: View {
    let text: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ok ? Theme.green : Theme.red)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ok ? Theme.green : Theme.red)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background((ok ? Theme.green : Theme.red).opacity(0.12))
        .clipShape(Capsule())
    }
}

struct ActionButton: View {
    let title: String
    let systemImage: String
    var prominent: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(prominent ? Theme.accent : Theme.cardAlt)
            .foregroundStyle(prominent ? Color.black : Theme.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(prominent ? Color.clear : Theme.stroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

enum Theme {
    static let background = Color.clear
    static let card = Color.white.opacity(0.10)
    static let cardAlt = Color.white.opacity(0.16)
    static let stroke = Color.white.opacity(0.18)
    static let accent = Color(red: 0.35, green: 0.95, blue: 0.75)
    static let accent2 = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.68)
    static let textTertiary = Color.white.opacity(0.35)
    static let green = Color(red: 0.35, green: 0.95, blue: 0.55)
    static let red = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.26)
}

struct PackageIcon: View {
    let image: UIImage?
    let name: String
    var size: CGFloat = 42

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        } else {
            AppIconTile(name: name, size: size)
        }
    }
}

struct AppIconTile: View {
    let name: String
    var size: CGFloat = 42

    private var letter: String {
        String(name.prefix(1)).uppercased()
    }

    private var seed: Int {
        abs(name.hashValue) % 4
    }

    private var gradient: [Color] {
        switch seed {
        case 0: return [Theme.accent.opacity(0.9), Color(red: 0.15, green: 0.55, blue: 0.75)]
        case 1: return [Theme.accent2.opacity(0.9), Color(red: 0.85, green: 0.35, blue: 0.2)]
        case 2: return [Color(red: 0.55, green: 0.9, blue: 0.5), Color(red: 0.2, green: 0.5, blue: 0.35)]
        default: return [Color(red: 0.95, green: 0.75, blue: 0.4), Color(red: 0.75, green: 0.45, blue: 0.15)]
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(letter)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.8))
        }
        .frame(width: size, height: size)
    }
}
