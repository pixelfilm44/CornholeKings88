import SwiftUI
internal import Combine

// MARK: - ViewModel (updated by CornholeBaseballScene via delegate)

final class BaseballHUDViewModel: ObservableObject {
    @Published var cycle:          Int = 1
    @Published var totalCycles:    Int = 3
    @Published var phaseIsbatting: Bool = true
    @Published var pitchCount:     Int = 0
    @Published var pitchesPerHalf: Int = 3
    @Published var playerAvgFt:    Int = 0
    @Published var aiAvgFt:        Int = 0
}

// MARK: - Root HUD View

struct BaseballHUDView: View {
    @ObservedObject var viewModel: BaseballHUDViewModel

    private let red  = Color(red: 0.831, green: 0.267, blue: 0.118)  // #d4441e
    private let gold = Color(red: 0.941, green: 0.753, blue: 0.376)  // #f0c060
    private let blue = Color(red: 0.353, green: 0.612, blue: 0.831)  // #5a9cd4

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
        }
    }

    // MARK: - Top bar: [leftStack] [cycleDots] [rightStack]  (close button added by UIKit)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            leftStack
            Spacer(minLength: 4)
            cycleDots
            Spacer(minLength: 4)
            rightStack
        }
        .padding(.leading, 12)
        .padding(.trailing, 60)   // leave room for the UIKit close button (44 + 8 + margin)
        .padding(.vertical, 10)
        .background(
            Color(red: 0.04, green: 0.02, blue: 0.01).opacity(0.92)
                .ignoresSafeArea(edges: .top)
                .overlay(
                    Rectangle()
                        .frame(height: 2)
                        .foregroundColor(Color(red: 0.35, green: 0.23, blue: 0.09)),
                    alignment: .bottom
                )
        )
    }

    // MARK: - Left stack: CYCLE x/y + YOU score

    private var leftStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CYCLE \(viewModel.cycle)/\(viewModel.totalCycles)")
                .font(.custom("PressStart2P-Regular", size: 9))
                .foregroundColor(red)
                .shadow(color: red.opacity(0.45), radius: 3)
                .fixedSize()
            Text("YOU: \(viewModel.playerAvgFt)ft")
                .font(.custom("PressStart2P-Regular", size: 9))
                .foregroundColor(red)
                .shadow(color: red.opacity(0.45), radius: 3)
                .fixedSize()
        }
    }

    // MARK: - Center: cycle-progress dots

    private var cycleDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<viewModel.totalCycles, id: \.self) { i in
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundColor(
                        i < viewModel.cycle
                            ? red
                            : Color(red: 0.290, green: 0.094, blue: 0.031)  // #4a1808
                    )
                    .shadow(color: i < viewModel.cycle ? red.opacity(0.7) : .clear, radius: 4)
                    .overlay(
                        Circle().stroke(Color(red: 0.13, green: 0.04, blue: 0.01), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Right stack: phase label + BOT score

    private var rightStack: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(viewModel.phaseIsbatting ? "YOU BAT" : "YOU PITCH")
                .font(.custom("PressStart2P-Regular", size: 9))
                .foregroundColor(gold)
                .shadow(color: gold.opacity(0.5), radius: 3)
                .fixedSize()
            Text("BOT: \(viewModel.aiAvgFt)ft")
                .font(.custom("PressStart2P-Regular", size: 9))
                .foregroundColor(blue)
                .shadow(color: blue.opacity(0.45), radius: 3)
                .fixedSize()
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
