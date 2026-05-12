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
                           color: Color(red: 0.83, green: 0.27, blue: 0.12))
                Spacer()
                pitchDots
                Spacer()
                scoreLabel(text: "BOT: \(viewModel.aiAvgFt)ft",
                           color: Color(red: 0.35, green: 0.61, blue: 0.83))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(
            Color(red: 0.04, green: 0.03, blue: 0.02).opacity(0.92)
                .ignoresSafeArea(edges: .top)
                .overlay(
                    Rectangle()
                        .frame(height: 2)
                        .foregroundColor(Color(red: 0.35, green: 0.23, blue: 0.09)),
                    alignment: .bottom
                )
        )
    }

    // MARK: Sub-views

    private var cycleLabel: some View {
        Text("CYCLE \(viewModel.cycle)/\(viewModel.totalCycles)")
            .font(.custom("PressStart2P-Regular", size: 10))
            .foregroundColor(Color(red: 0.83, green: 0.27, blue: 0.12))
    }

    private var phaseLabel: some View {
        Text(viewModel.phaseIsbatting ? "YOU BAT" : "YOU PITCH")
            .font(.custom("PressStart2P-Regular", size: 10))
            .foregroundColor(Color(red: 0.78, green: 0.57, blue: 0.16))
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
                            ? Color(red: 0.83, green: 0.27, blue: 0.12)
                            : Color(white: 0.25)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.35, green: 0.23, blue: 0.09), lineWidth: 1)
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
