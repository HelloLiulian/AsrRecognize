import SwiftUI

// MARK: - Background

struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.accent.opacity(0.16))
                .frame(width: 460, height: 460)
                .blur(radius: 140)
                .offset(x: drift ? 130 : -110, y: drift ? -300 : -220)
            Circle()
                .fill(Theme.violet.opacity(0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 150)
                .offset(x: drift ? -150 : 120, y: drift ? 340 : 260)
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 16).repeatForever(autoreverses: true),
            value: drift
        )
        .onAppear { drift = true }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Interaction

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Surfaces

struct GlassCard: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(padding: CGFloat = 18, radius: CGFloat = 22) -> some View {
        modifier(GlassCard(padding: padding, radius: radius))
    }
}

// MARK: - Text bits

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.8)
            .foregroundStyle(Theme.textTertiary)
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = Theme.accent
    var pulse: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .opacity(pulse && animate && !reduceMotion ? 0.28 : 1)
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(color.opacity(0.1)))
        .overlay(Capsule().strokeBorder(color.opacity(0.24), lineWidth: 1))
        .onAppear {
            guard pulse, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Buttons

struct PillButton: View {
    enum Kind {
        case primary, secondary, danger
    }

    let title: String
    var icon: String? = nil
    var kind: Kind = .primary
    var fullWidth: Bool = true
    let action: () -> Void

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return Theme.textPrimary
        case .danger: return Theme.record
        }
    }

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 48)
            .padding(.horizontal, fullWidth ? 0 : 20)
            .background {
                switch kind {
                case .primary:
                    Capsule().fill(
                        LinearGradient(
                            colors: [Theme.accent, Color(hex: 0x3F6BFF)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                case .secondary:
                    Capsule().fill(Theme.cardFill)
                case .danger:
                    Capsule().fill(Theme.record.opacity(0.14))
                }
            }
            .overlay {
                Capsule().strokeBorder(
                    kind == .primary ? Color.white.opacity(0.18) : Theme.stroke,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Loading / empty

struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.white.opacity(dim ? 0.045 : 0.1))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .onAppear {
                guard !reduceMotion else {
                    dim = true
                    return
                }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.cardFill)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Segmented control

struct CapsuleSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    guard selection != option.value else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = option.value
                    }
                    Haptics.selection()
                } label: {
                    Text(option.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == option.value ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selection == option.value {
                                Capsule()
                                    .fill(Theme.elevated)
                                    .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.32)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Transcript row

struct TranscriptRow: View {
    let segment: TranscriptSegment
    var isPartial: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(AppFormat.clock(segment.timestamp))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 42, alignment: .leading)
                .padding(.top, 4)
            Text(segment.text)
                .font(.system(size: 15))
                .foregroundStyle(isPartial ? Theme.accentBright : Theme.textPrimary.opacity(0.92))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
