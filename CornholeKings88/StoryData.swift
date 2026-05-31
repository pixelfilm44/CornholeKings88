import SpriteKit

// MARK: - Story flags (world-state gates persisted across launches)

enum StoryFlag: String, CaseIterable {
    case dogsEnabled        // dogs start chasing Jeff
    case baseballEnabled    // baseball tile becomes interactive
    case batFound           // bat pickup has been collected
    case questAccepted      // Master Board quest is active
    case bulliesEnabled     // Billy's gang roams the map and ambushes Jeff
}

// MARK: - Baseball AI style

enum BaseballAIDifficulty {
    case standard
    case powerHitter    // Jen — wide, hard-to-field hits
    case greatFielder   // Tom — tight fielding, covers more ground
    case fastPitcher    // free-play Jen — faster pitches, harder to time
}

// MARK: - Mini-game types that story modules can trigger

enum StoryMiniGame {
    case cornholeVs(opponent: CornholeMiniGameScene.AIOpponent)
    case baseballVs(difficulty: BaseballAIDifficulty)
    case beehive
    case bike
}

// MARK: - Spawn configuration (used by StoryOutcome.spawnOnMap)

struct StorySpawnConfig {
    /// World position; nil = use the map's default Spawn layer tile.
    let x: CGFloat?
    let y: CGFloat?
    /// World trigger GameScene checks on A-press near the matching tile/object.
    let trigger: String?
    /// Sets StoryManager.currentModuleID before spawning so re-entry resumes here.
    let nextModuleID: String?
    /// Story flags to set before spawning.
    let flags: [StoryFlag]

    init(x: CGFloat? = nil, y: CGFloat? = nil,
         trigger: String? = nil, nextModuleID: String? = nil,
         flags: [StoryFlag] = []) {
        self.x = x; self.y = y
        self.trigger = trigger; self.nextModuleID = nextModuleID
        self.flags = flags
    }
}

// MARK: - What happens after a story module resolves

indirect enum StoryOutcome {
    case nextModule(id: String)
    case spawnOnMap(StorySpawnConfig)
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
    let imageColor: SKColor     // placeholder fill until real assets are added
    let text: String
    let choices: [StoryChoice]  // empty → tap-to-continue using autoOutcome
    let autoOutcome: StoryOutcome
}

// MARK: - Progress & state persistence

final class StoryManager {
    static let shared = StoryManager()
    private init() {}

    static let firstModuleID = "p1_birthday"

    private static let progressKey = "storyCurrentModuleID_v1"
    private static let triggerKey  = "storyWorldTrigger_v1"
    private static let flagsKey    = "storyFlags_v1"

    // --- Current module ---

    var currentModuleID: String {
        get { UserDefaults.standard.string(forKey: Self.progressKey) ?? Self.firstModuleID }
        set { UserDefaults.standard.set(newValue, forKey: Self.progressKey) }
    }

    var currentModule: StoryModule? { module(id: currentModuleID) }

    func module(id: String) -> StoryModule? {
        StoryContent.all.first { $0.id == id }
    }

    // --- World trigger ---

    var pendingWorldTrigger: String? {
        get { UserDefaults.standard.string(forKey: Self.triggerKey) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: Self.triggerKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.triggerKey) }
        }
    }

    // --- Story flags ---

    func hasFlag(_ flag: StoryFlag) -> Bool {
        let stored = UserDefaults.standard.stringArray(forKey: Self.flagsKey) ?? []
        return stored.contains(flag.rawValue)
    }

    func setFlag(_ flag: StoryFlag) {
        var stored = UserDefaults.standard.stringArray(forKey: Self.flagsKey) ?? []
        guard !stored.contains(flag.rawValue) else { return }
        stored.append(flag.rawValue)
        UserDefaults.standard.set(stored, forKey: Self.flagsKey)
    }

    // --- Reset ---

    func reset() {
        UserDefaults.standard.removeObject(forKey: Self.progressKey)
        UserDefaults.standard.removeObject(forKey: Self.triggerKey)
        UserDefaults.standard.removeObject(forKey: Self.flagsKey)
    }
}

// MARK: - World trigger string constants (shared with GameScene)

extension StoryManager {
    static let triggerCornhole   = "cornhole_story"
    static let triggerBat        = "bat_story"
    static let triggerBaseball   = "baseball_story"
    static let triggerBridge     = "bridge_story"
    static let triggerQuestOffer = "quest_offer"

    // Bat world position — tune to match the actual map layout.
    static let batWorldPosition = CGPoint(x: 380, y: 260)
}

// MARK: - Part 1 story content

enum StoryContent {
    static let all: [StoryModule] = [

        // ── Opening birthday cutscene ──────────────────────────────────────────
        StoryModule(
            id: "p1_birthday",
            title: "A MAGICAL GIFT",
            imageColor: SKColor(red: 0.18, green: 0.38, blue: 0.55, alpha: 1),
            text: "On his 11th birthday, Jeff received the most magical of gifts — a wooden cornhole set.\n\nLife in the backyard would never be the same again for him and his friends...",
            choices: [],
            autoOutcome: .nextModule(id: "p1_last_day")
        ),

        // ── Last day of school — bike race setup ───────────────────────────────
        StoryModule(
            id: "p1_last_day",
            title: "LAST DAY OF SCHOOL",
            imageColor: SKColor(red: 0.55, green: 0.72, blue: 0.30, alpha: 1),
            text: "On the last day of school, Jeff, his brother Tom and their friend Jen raced home on their bikes.\n\nThey couldn't wait for their first cornhole tournament!\n\nBut first Jeff had to survive the deadly traffic — and the bean bags thrown by Billy the Bully's gang of thugs.",
            choices: [],
            autoOutcome: .miniGame(.bike, winID: "p1_race_win", loseID: "p1_race_retry")
        ),

        // ── Bike race loss ─────────────────────────────────────────────────────
        StoryModule(
            id: "p1_race_retry",
            title: "WIPEOUT!",
            imageColor: SKColor(red: 0.60, green: 0.18, blue: 0.18, alpha: 1),
            text: "You went down hard!\n\nBilly's gang is still laughing.\n\nGet back up and try again?",
            choices: [
                StoryChoice(label: "TRY AGAIN",
                            outcome: .miniGame(.bike, winID: "p1_race_win", loseID: "p1_race_retry")),
                StoryChoice(label: "GIVE UP",
                            outcome: .spawnOnMap(StorySpawnConfig(nextModuleID: "p1_last_day")))
            ],
            autoOutcome: .miniGame(.bike, winID: "p1_race_win", loseID: "p1_race_retry")
        ),

        // ── Bike race win — spawn on map, find cornhole board ──────────────────
        StoryModule(
            id: "p1_race_win",
            title: "CLOSE RACE!",
            imageColor: SKColor(red: 0.72, green: 0.58, blue: 0.12, alpha: 1),
            text: "\"Close race!\" says Jen.\n\nTom chimes in, \"Next time I will beat you. Cars were crazy today!\"\n\n\"Now let's find that cornhole board!\"",
            choices: [],
            autoOutcome: .spawnOnMap(StorySpawnConfig(
                trigger: StoryManager.triggerCornhole,
                nextModuleID: "p1_jen_intro"))
        ),

        // ── Player approaches cornhole board — Jen match ───────────────────────
        StoryModule(
            id: "p1_jen_intro",
            title: "JEN IS UP FIRST",
            imageColor: SKColor(red: 0.30, green: 0.55, blue: 0.35, alpha: 1),
            text: "\"Jen is up first,\" says Tom with a grin.\n\nCan Jeff beat her, or will he fall in defeat?",
            choices: [],
            autoOutcome: .miniGame(.cornholeVs(opponent: .jenny),
                                   winID: "p1_jen_win",
                                   loseID: "p1_jen_lose")
        ),

        // ── Beat Jen — Tom match ───────────────────────────────────────────────
        StoryModule(
            id: "p1_jen_win",
            title: "TOM IS UP NEXT",
            imageColor: SKColor(red: 0.55, green: 0.40, blue: 0.18, alpha: 1),
            text: "\"Nice throws!\" says Tom, stepping up to the board.\n\n\"Can you defeat the Tomster? Or will his sticky toots distract you too much?\"",
            choices: [],
            autoOutcome: .miniGame(.cornholeVs(opponent: .tom),
                                   winID: "p1_tom_win",
                                   loseID: "p1_tom_lose")
        ),

        // ── Lose to Jen ────────────────────────────────────────────────────────
        StoryModule(
            id: "p1_jen_lose",
            title: "NOT THIS TIME",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Jen pulls off the win!\n\n\"Better luck next time,\" she says with a smirk.\n\nWhat will you do?",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.cornholeVs(opponent: .jenny),
                                               winID: "p1_jen_win",
                                               loseID: "p1_jen_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .spawnOnMap(StorySpawnConfig(
                                trigger: StoryManager.triggerCornhole,
                                nextModuleID: "p1_jen_intro")))
            ],
            autoOutcome: .miniGame(.cornholeVs(opponent: .jenny),
                                   winID: "p1_jen_win",
                                   loseID: "p1_jen_lose")
        ),

        // ── Beat Tom in cornhole — find the bat ────────────────────────────────
        StoryModule(
            id: "p1_tom_win",
            title: "BASEBALL!",
            imageColor: SKColor(red: 0.25, green: 0.50, blue: 0.68, alpha: 1),
            text: "Tom asks, \"What else can we do with cornhole?\"\n\nJen's eyes light up. \"Baseball! But we need to find the bat. There must be one around here somewhere!\"\n\n\"Let's go find it!\"",
            choices: [],
            autoOutcome: .spawnOnMap(StorySpawnConfig(
                trigger: StoryManager.triggerBat,
                nextModuleID: "p1_bat_found",
                flags: [.dogsEnabled, .bulliesEnabled]))
        ),

        // ── Lose to Tom in cornhole ────────────────────────────────────────────
        StoryModule(
            id: "p1_tom_lose",
            title: "CLOSE ONE",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Tom lets out a victory toot.\n\n\"My house, my rules,\" he boasts.\n\nWhat will you do?",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.cornholeVs(opponent: .tom),
                                               winID: "p1_tom_win",
                                               loseID: "p1_tom_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .spawnOnMap(StorySpawnConfig(
                                trigger: StoryManager.triggerCornhole,
                                nextModuleID: "p1_jen_win")))
            ],
            autoOutcome: .miniGame(.cornholeVs(opponent: .tom),
                                   winID: "p1_tom_win",
                                   loseID: "p1_tom_lose")
        ),

        // ── Player finds the bat ───────────────────────────────────────────────
        StoryModule(
            id: "p1_bat_found",
            title: "FOUND IT!",
            imageColor: SKColor(red: 0.62, green: 0.45, blue: 0.18, alpha: 1),
            text: "\"Found the bat!\" Jeff holds it up triumphantly.\n\n\"Now we can really play baseball,\" Jen cheers.\n\nTom grins. \"First one to beat both of us wins bragging rights forever.\"\n\nBeat Jen AND Tom at cornhole baseball!",
            choices: [],
            autoOutcome: .spawnOnMap(StorySpawnConfig(
                trigger: StoryManager.triggerBaseball,
                nextModuleID: "p1_baseball_jen_intro",
                flags: [.batFound, .baseballEnabled]))
        ),

        // ── Baseball vs Jen ────────────────────────────────────────────────────
        StoryModule(
            id: "p1_baseball_jen_intro",
            title: "JEN BATS FIRST",
            imageColor: SKColor(red: 0.30, green: 0.55, blue: 0.35, alpha: 1),
            text: "Jen steps up to the plate with a dangerous look.\n\nShe's a power hitter — her shots go far and wide.\n\nCan you field everything she sends your way?",
            choices: [],
            autoOutcome: .miniGame(.baseballVs(difficulty: .powerHitter),
                                   winID: "p1_baseball_jen_win",
                                   loseID: "p1_baseball_jen_lose")
        ),

        // ── Beat Jen at baseball — Tom match ──────────────────────────────────
        StoryModule(
            id: "p1_baseball_jen_win",
            title: "TOM STEPS UP",
            imageColor: SKColor(red: 0.55, green: 0.40, blue: 0.18, alpha: 1),
            text: "\"Lucky,\" mutters Jen.\n\nTom cracks his knuckles. \"My turn. I may not hit as hard, but I'll catch everything you throw.\"\n\nTom is a great fielder. No easy passes!",
            choices: [],
            autoOutcome: .miniGame(.baseballVs(difficulty: .greatFielder),
                                   winID: "p1_baseball_tom_win",
                                   loseID: "p1_baseball_tom_lose")
        ),

        // ── Lose to Jen at baseball ────────────────────────────────────────────
        StoryModule(
            id: "p1_baseball_jen_lose",
            title: "STRUCK OUT",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Jen's power was just too much.\n\n\"I'll let you try again,\" she says generously.",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.baseballVs(difficulty: .powerHitter),
                                               winID: "p1_baseball_jen_win",
                                               loseID: "p1_baseball_jen_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .spawnOnMap(StorySpawnConfig(
                                trigger: StoryManager.triggerBaseball,
                                nextModuleID: "p1_baseball_jen_intro")))
            ],
            autoOutcome: .miniGame(.baseballVs(difficulty: .powerHitter),
                                   winID: "p1_baseball_jen_win",
                                   loseID: "p1_baseball_jen_lose")
        ),

        // ── Beat Tom at baseball — Master Board speech ─────────────────────────
        StoryModule(
            id: "p1_baseball_tom_win",
            title: "THE LEGEND",
            imageColor: SKColor(red: 0.18, green: 0.32, blue: 0.58, alpha: 1),
            text: "Jen's expression turns mysterious.\n\n\"Have you heard the legend of the Master Board? It's a board made with wood from the Mayflower. Sink three cornholes in one game and it grants you any wish!\"\n\nShe pauses. \"I want to find it. Are you in?\"",
            choices: [
                StoryChoice(label: "ACCEPT",
                            outcome: .nextModule(id: "p1_quest_accept")),
                StoryChoice(label: "FORGET IT",
                            outcome: .spawnOnMap(StorySpawnConfig(
                                trigger: StoryManager.triggerQuestOffer,
                                nextModuleID: "p1_baseball_tom_win")))
            ],
            autoOutcome: .nextModule(id: "p1_quest_accept")
        ),

        // ── Lose to Tom at baseball ────────────────────────────────────────────
        StoryModule(
            id: "p1_baseball_tom_lose",
            title: "NICE TRY",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Tom's fielding was air-tight.\n\n\"I caught everything,\" he says smugly.\n\nWant another shot?",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.baseballVs(difficulty: .greatFielder),
                                               winID: "p1_baseball_tom_win",
                                               loseID: "p1_baseball_tom_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .spawnOnMap(StorySpawnConfig(
                                trigger: StoryManager.triggerBaseball,
                                nextModuleID: "p1_baseball_jen_win")))
            ],
            autoOutcome: .miniGame(.baseballVs(difficulty: .greatFielder),
                                   winID: "p1_baseball_tom_win",
                                   loseID: "p1_baseball_tom_lose")
        ),

        // ── Quest accepted ─────────────────────────────────────────────────────
        StoryModule(
            id: "p1_quest_accept",
            title: "THE QUEST BEGINS",
            imageColor: SKColor(red: 0.45, green: 0.28, blue: 0.08, alpha: 1),
            text: "\"Great!\" beams Jen. \"First we must get into the woods to search for the board.\"\n\nShe pulls a crinkled map from her pocket.\n\n\"I found this in a box of Cracker Jacks. There's an old bridge that leads to the forest. Let's go!\"",
            choices: [],
            autoOutcome: .spawnOnMap(StorySpawnConfig(
                trigger: StoryManager.triggerBridge,
                nextModuleID: "p1_bridge_intro",
                flags: [.questAccepted]))
        ),

        // ── Bridge encounter — end of Part 1 ──────────────────────────────────
        StoryModule(
            id: "p1_bridge_intro",
            title: "THE RIVER",
            imageColor: SKColor(red: 0.12, green: 0.28, blue: 0.48, alpha: 1),
            text: "The kids approach the old bridge — and stop dead.\n\nTom gulps. \"We have no way to cross! We could try walking through the river, but it's filled with hungry piranhas!\"\n\nJen frowns. \"We need something that floats...\"",
            choices: [],
            autoOutcome: .spawnOnMap(StorySpawnConfig(
                nextModuleID: "p1_bridge_intro"))
        ),
    ]
}
