import SwiftUI

struct LiveWaveform: View {
    var level: CGFloat
    var isActive: Bool

    private let barCount = 48
    @State private var history: [CGFloat] = Array(repeating: 0.12, count: 48)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                let slot = size.width / CGFloat(barCount)
                let barWidth = max(2, slot * 0.38)

                for index in 0..<barCount {
                    let progress = Double(index) / Double(barCount - 1)
                    let envelope = sin(progress * .pi)
                    let wave = (sin(time * 2.4 + progress * 9.0) + 1) / 2
                    let sample = Double(history[min(index, history.count - 1)])
                    let energy = isActive ? sample * (0.6 + 0.4 * wave) : 0.03
                    let height = max(3, CGFloat(energy) * 70 * CGFloat(0.35 + envelope * 0.85))
                    let x = CGFloat(index) * slot + (slot - barWidth) / 2
                    let rect = CGRect(
                        x: x,
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [Theme.cyan.opacity(0.95), Theme.accent.opacity(0.9)]),
                        startPoint: CGPoint(x: x, y: size.height / 2 - height / 2),
                        endPoint: CGPoint(x: x, y: size.height / 2 + height / 2)
                    )
                    context.fill(path, with: shading)
                }
            }
        }
        .onChange(of: level) { _, newValue in
            var next = history
            next.removeFirst()
            next.append(min(1, max(0.02, newValue)))
            history = next
        }
        .accessibilityHidden(true)
    }
}
