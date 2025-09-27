import SwiftUI

struct AnimatedStrikeText: View {
    let text: String
    let isStruck: Bool
    var lineHeight: CGFloat = 2
    var lineColor: Color = Colors.onSurfaceVariant

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fullWidth: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .style(Typography.headline)
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { fullWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newValue in fullWidth = newValue }
                })
            Rectangle()
                .fill(lineColor)
                .frame(width: isStruck ? fullWidth : 0, height: lineHeight)
                .opacity(isStruck ? 1 : 0.0)
                .offset(y: 0) // centered; headline has sufficient x-height for readability
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isStruck)
        }
    }
}


