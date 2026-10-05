import SwiftUI

@Observable
final class NotchState {
    var isExpanded = false
    var collapsedWidth: CGFloat = 200
    var expandedWidth: CGFloat = 380
    var collapsedHeight: CGFloat = 0
    var expandedHeight: CGFloat = 124

    /// Tamanho interpolado da pílula, usado pelo hit testing. Não é lido pela view.
    var onPillSizeChange: ((CGSize) -> Void)?

    static let collapsedCornerRadius: CGFloat = 16
    static let expandedCornerRadius: CGFloat = 28
    static let animationDuration: TimeInterval = 0.35

    func cornerRadius(forHeight height: CGFloat) -> CGFloat {
        let span = expandedHeight - collapsedHeight
        guard span > 0.5 else { return Self.collapsedCornerRadius }
        let progress = min(1, max(0, (height - collapsedHeight) / span))
        return Self.collapsedCornerRadius + (Self.expandedCornerRadius - Self.collapsedCornerRadius) * progress
    }
}

struct ContentView: View {
    var state: NotchState

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: state.isExpanded ? NotchState.expandedCornerRadius : NotchState.collapsedCornerRadius,
            bottomTrailingRadius: state.isExpanded ? NotchState.expandedCornerRadius : NotchState.collapsedCornerRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    private var pillWidth: CGFloat {
        state.isExpanded ? state.expandedWidth : state.collapsedWidth
    }

    private var pillHeight: CGFloat {
        state.isExpanded ? state.expandedHeight : state.collapsedHeight
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .frame(width: pillWidth, height: pillHeight)
                .overlay {
                    if state.isExpanded {
                        Text("Hello World")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .clipShape(shape)
                .background {
                    PillSizeReporter(width: pillWidth, height: pillHeight) { size in
                        state.onPillSizeChange?(size)
                    }
                }
        }
        .animation(.smooth(duration: NotchState.animationDuration), value: state.isExpanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}

/// Entrega largura e altura já interpoladas, inclusive nos frames intermediários da animação.
private struct PillSizeReporter: View, Animatable {
    var width: CGFloat
    var height: CGFloat
    var onChange: (CGSize) -> Void

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set {
            width = newValue.first
            height = newValue.second
            onChange(CGSize(width: width, height: height))
        }
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onAppear { onChange(CGSize(width: width, height: height)) }
            .onChange(of: width) { _, newWidth in
                onChange(CGSize(width: newWidth, height: height))
            }
            .onChange(of: height) { _, newHeight in
                onChange(CGSize(width: width, height: newHeight))
            }
    }
}
