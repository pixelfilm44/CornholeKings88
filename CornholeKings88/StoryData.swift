import SpriteKit

// MARK: - Mini-game types that story modules can trigger

enum StoryMiniGame {
    case cornhole
    case baseball
    case beehive
    case bike
}

// MARK: - What happens after a story module resolves

indirect enum StoryOutcome {
    case nextModule(id: String)
    case spawnOnMap(x: CGFloat, y: CGFloat)
    case miniGame(_ type: StoryMiniGame, winID: String?, loseID: String?)
    case returnToMenu
}

// MARK: - A single player choice shown as a button

struct StoryChoice {
    let label: String
    let outcome: StoryOutcome
}

// MARK: - A single story beat: image + text + choices or auto-advance

struct StoryModule {
    let id: String
    let title: String
    let imageColor: SKColor     // placeholder fill color until real assets are added
    let text: String
    let choices: [StoryChoice]  // empty → tap-to-continue using autoOutcome
    let autoOutcome: StoryOutcome
}

// MARK: - Progress persistence

final class StoryManager {
    static let shared = StoryManager()
    private init() {}

    static let firstModuleID = "intro_01"
    private static let progressKey = "storyCurrentModuleID_v1"

    var currentModuleID: String {
        get { UserDefaults.standard.string(forKey: Self.progressKey) ?? Self.firstModuleID }
        set { UserDefaults.standard.set(newValue, forKey: Self.progressKey) }
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: Self.progressKey)
    }

    func module(id: String) -> StoryModule? {
        StoryContent.all.first { $0.id == id }
    }

    var currentModule: StoryModule? {
        module(id: currentModuleID)
    }
}

// MARK: - Placeholder story content

enum StoryContent {
    static let all: [StoryModule] = [

        StoryModule(
            id: "intro_01",
            title: "A NEW DAY",
            imageColor: SKColor(red: 0.18, green: 0.42, blue: 0.28, alpha: 1),
            text: "You open your eyes.\n\nThe sky is wide and blue. Somewhere in the distance, a crowd is cheering.",
            choices: [],
            autoOutcome: .nextModule(id: "intro_02")
        ),

        StoryModule(
            id: "intro_02",
            title: "THE KINGDOM",
            imageColor: SKColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1),
            text: "A painted sign reads:\n\n\"WELCOME TO CORNHOLE KINGDOM\"\n\nYou feel the call of adventure. What will you do?",
            choices: [
                StoryChoice(label: "PLAY NOW",  outcome: .nextModule(id: "qualify_01")),
                StoryChoice(label: "EXPLORE",   outcome: .spawnOnMap(x: 240, y: 200))
            ],
            autoOutcome: .nextModule(id: "qualify_01")
        ),

        StoryModule(
            id: "qualify_01",
            title: "QUALIFYING",
            imageColor: SKColor(red: 0.70, green: 0.58, blue: 0.10, alpha: 1),
            text: "The qualifier board lights up.\n\n\"LAND THREE BAGS TO ADVANCE TO THE CHAMPIONSHIP!\"\n\nYou step up to the line.",
            choices: [],
            autoOutcome: .miniGame(.cornhole, winID: "qualify_win", loseID: "qualify_lose")
        ),

        StoryModule(
            id: "qualify_win",
            title: "CHAMPION!",
            imageColor: SKColor(red: 0.75, green: 0.62, blue: 0.08, alpha: 1),
            text: "PERFECT THROWS!\n\nThe crowd erupts. Confetti rains down.\n\n\"CORNHOLE KING!\" they chant as you walk into the kingdom.",
            choices: [],
            autoOutcome: .spawnOnMap(x: 300, y: 300)
        ),

        StoryModule(
            id: "qualify_lose",
            title: "SETBACK",
            imageColor: SKColor(red: 0.45, green: 0.10, blue: 0.10, alpha: 1),
            text: "Not your best round.\n\nThe crowd is quiet. But legends are built on setbacks.\n\nYou set out to explore and train.",
            choices: [],
            autoOutcome: .spawnOnMap(x: 120, y: 120)
        ),
    ]
}
