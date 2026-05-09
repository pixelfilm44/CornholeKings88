import SwiftUI
internal import Combine

// MARK: - ViewModel (updated by CornholeBaseballScene via delegate)

final class BaseballHUDViewModel: ObservableObject {
    @Published var cycle:          Int = 1
    @Published var totalCycles:    Int = 3
    @Published var phaseIsbatting: Bool = true   // true = YOU BAT, false = YOU PITCH
    @Published var pitchCount:     Int = 0
    @Published var pitchesPerHalf: Int = 3
    @Published var playerAvgFt:    Int = 0
    @Published var aiAvgFt:        Int = 0
}

// MARK: - Root HUD View (transparent overlay; HUD lives only at the top)

struct BaseballHUDView: View {
    @ObservedObject var viewModel: BaseballHUDViewModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(spacing: 4) {
            // Row 1: Cycle · Phase label · close hint
            HStack(alignment: .center) {
                cycleLabel
                Spacer()
                phaseLabel
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Row 2: Player avg · pitch dots · AI avg
            HStack(alignment: .center) {
                scoreLabel(text: "YOU: \(viewModel.playerAvgFt)ft",
                           color: Color(red: 0.90, green: 0.42, blue: 0.42))
                Spacer()
                pitchDots
                Spacer()
                scoreLabel(text: "BOT: \(viewModel.aiAvgFt)ft",
                           color: Color(red: 0.40, green: 0.60, blue: 0.90))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(
            Color.black.opacity(0.82)
                .ignoresSafeArea(edges: .top)
                .overlay(
                    Rectangle()
                        .frame(height: 1.5)
                        .foregroundColor(Color(red: 0.55, green: 0.38, blue: 0.14)),
                    alignment: .bottom
                )
        )
    }

    // MARK: Sub-views

    private var cycleLabel: some View {
        Text("CYCLE \(viewModel.cycle)/\(viewModel.totalCycles)")
            .font(.custom("PressStart2P-Regular", size: 10))
            .foregroundColor(Color(white: 0.75))
    }

    private var phaseLabel: some View {
        Text(viewModel.phaseIsbatting ? "YOU BAT" : "YOU PITCH")
            .font(.custom("PressStart2P-Regular", size: 10))
            .foregroundColor(
                viewModel.phaseIsbatting
                    ? Color(red: 0.30, green: 0.85, blue: 0.30)
                    : Color(red: 1.00, green: 0.32, blue: 0.32)
            )
    }

    private func scoreLabel(text: String, color: Color) -> some View {
        Text(text)
            .font(.custom("PressStart2P-Regular", size: 9))
            .foregroundColor(color)
    }

    private var pitchDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<viewModel.pitchesPerHalf, id: \.self) { i in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundColor(
                        i < viewModel.pitchCount
                            ? Color(red: 0.95, green: 0.25, blue: 0.25)
                            : Color(white: 0.35)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(white: 0.55), lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(red: 0.13, green: 0.30, blue: 0.10).ignoresSafeArea()
        BaseballHUDView(viewModel: {
            let vm = BaseballHUDViewModel()
            vm.cycle = 2
            vm.phaseIsbatting = false
            vm.pitchCount = 1
            vm.playerAvgFt = 142
            vm.aiAvgFt = 118
            return vm
        }())
    }
}
