import SwiftUI
internal import Combine

// MARK: - ViewModel (updated by CornholeBaseballScene via delegate)

final class BaseballHUDViewModel: ObservableObject {
    @Published var cycle:          Int = 1
    @Published var totalCycles:    Int = 3
    @Published var phaseIsbatting: Bool = true
    @Published var outs:           Int = 0
    @Published var strikes:        Int = 0
    @Published var playerAvgFt:    Int = 0
    @Published var aiAvgFt:        Int = 0
    @Published var opponentName:   String = "BOT"
}

// MARK: - Root HUD View

struct BaseballHUDView: View {
    @ObservedObject var viewModel: BaseballHUDViewModel

    private let gold      = Color(red: 0.941, green: 0.753, blue: 0.376) // #f0c060
    private let red       = Color(red: 0.831, green: 0.267, blue: 0.118) // #d4441e
    private let blue      = Color(red: 0.353, green: 0.612, blue: 0.831) // #5a9cd4
    private let primary   = Color(red: 0.102, green: 0.039, blue: 0.016) // #1a0a04
    private let ironGray  = Color(red: 0.349, green: 0.349, blue: 0.349) // #595959

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
        }
    }

    // MARK: - Top ribbon: 48pt + safe area, solid #1a0a04, 2px gold bottom border

    private var topBar: some View {
        HStack(alignment: .center, spacing: 0) {
            // Zone A — space for SK pauseIcon (44pt)
            Spacer().frame(width: 44)

            Spacer(minLength: 0)

            // Zone B — center content
            VStack(spacing: 4) {
                // Inning label + progress pips
                HStack(spacing: 8) {
                    Text("INNING \(viewModel.cycle)/\(viewModel.totalCycles)")
                        .font(.custom("PressStart2P-Regular", size: 8))
                        .foregroundColor(gold)
                        .fixedSize()

                    HStack(spacing: 4) {
                        ForEach(0..<viewModel.totalCycles, id: \.self) { i in
                            Rectangle()
                                .frame(width: 10, height: 10)
                                .foregroundColor(i < viewModel.cycle ? red : ironGray.opacity(0.4))
                                .overlay(
                                    Rectangle().stroke(ironGray, lineWidth: 1)
                                )
                        }
                    }
                }

                // Score row
                HStack(spacing: 6) {
                    Text("YOU: \(viewModel.playerAvgFt)ft")
                        .font(.custom("PressStart2P-Regular", size: 8))
                        .foregroundColor(red)
                        .fixedSize()
                    Text("|")
                        .font(.custom("PressStart2P-Regular", size: 8))
                        .foregroundColor(ironGray)
                    Text("\(viewModel.opponentName): \(viewModel.aiAvgFt)ft")
                        .font(.custom("PressStart2P-Regular", size: 8))
                        .foregroundColor(blue)
                        .fixedSize()
                }

                // Count row — outs (red) and strikes (gold) for the current batter
                HStack(spacing: 8) {
                    countGroup(label: "OUT", count: viewModel.outs, total: 3, color: red)
                    countGroup(label: "STR", count: viewModel.strikes, total: 3, color: gold)
                }
            }

            Spacer(minLength: 0)

            // Zone C — space for SK closeIcon (44pt)
            Spacer().frame(width: 44)
        }
        .padding(.vertical, 8)
        .background(
            primary
                .ignoresSafeArea(edges: .top)
                .overlay(
                    Rectangle()
                        .frame(height: 2)
                        .foregroundColor(gold),
                    alignment: .bottom
                )
        )
    }

    /// A labelled row of small pips ("OUT ● ● ○"), filled up to `count`.
    private func countGroup(label: String, count: Int, total: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.custom("PressStart2P-Regular", size: 7))
                .foregroundColor(ironGray)
                .fixedSize()
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .frame(width: 7, height: 7)
                        .foregroundColor(i < count ? color : ironGray.opacity(0.35))
                }
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
            vm.phaseIsbatting = true
            vm.outs = 1
            vm.strikes = 2
            vm.playerAvgFt = 142
            vm.aiAvgFt = 118
            return vm
        }())
    }
}
