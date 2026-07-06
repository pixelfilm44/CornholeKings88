import SpriteKit

// MARK: - Story flags (world-state gates persisted across launches)

enum StoryFlag: String, CaseIterable {
    case dogsEnabled        // dogs start chasing Jack
    case baseballEnabled    // baseball tile becomes interactive
    case batFound           // bat pickup has been collected
    case questAccepted      // legacy flag, unused by current content
    case bulliesEnabled     // Billy Badger's gang roams the map and ambushes Jack
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
    case piranha
    case beachball
    case jousters
    case horseRace
    case wellFlinger
    case kickball
    case mopChase
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

    static let firstModuleID = "p1_intro"

    private static let progressKey = "storyCurrentModuleID_v1"
    private static let triggerKey  = "storyWorldTrigger_v1"
    private static let flagsKey    = "storyFlags_v1"

    /// Old module IDs (from the Master Board quest chain) mapped to the nearest
    /// equivalent checkpoint in the current narrative, so returning players never
    /// resume at a module that no longer exists.
    private static let legacyModuleMap: [String: String] = [
        "p1_tom_win":            "p1_jen_win",
        "p1_tom_lose":           "p1_jen_win",
        "p1_bat_found":          "p1_jen_win",
        "p1_baseball_jen_intro": "p1_jen_win",
        "p1_baseball_jen_win":   "p1_jen_win",
        "p1_baseball_jen_lose":  "p1_jen_win",
        "p1_baseball_tom_win":   "p1_jen_win",
        "p1_baseball_tom_lose":  "p1_jen_win",
        "p1_quest_accept":       "p1_jen_win",
        "p1_bridge_intro":       "p1_jen_win",
    ]

    // --- Current module ---

    var currentModuleID: String {
        get {
            let raw = UserDefaults.standard.string(forKey: Self.progressKey) ?? Self.firstModuleID
            if StoryContent.all.contains(where: { $0.id == raw }) { return raw }
            return Self.legacyModuleMap[raw] ?? Self.firstModuleID
        }
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
    static let triggerCave       = "cave_story"
    static let triggerAppleTree  = "appletree_story"

    // Bat world position — tune to match the actual map layout.
    static let batWorldPosition = CGPoint(x: 380, y: 260)
}

// MARK: - Part 1 story content

enum StoryContent {
    static let all: [StoryModule] = [

        // ── PROLOGUE ───────────────────────────────────────────────────────────

        StoryModule(
            id: "p1_intro",
            title: "SUMMER OF '88",
            imageColor: SKColor(red: 0.18, green: 0.38, blue: 0.55, alpha: 1),
            text: "It was the beginning of the summer of '88 and Jack had just turned 12.\n\nHis best friend Steve had just moved away, and Jack never felt more alone. Girls were still way too scary, and lunchroom seats felt like broken jets looking for an emergency landing.",
            choices: [],
            autoOutcome: .nextModule(id: "p1_kim_call")
        ),

        StoryModule(
            id: "p1_kim_call",
            title: "THE THREE-WAY CALL",
            imageColor: SKColor(red: 0.55, green: 0.35, blue: 0.55, alpha: 1),
            text: "There was Kim — kind blue eyes, a walk-home-from-the-bus-stop kind of crush. Jack was sure she was his destiny.\n\nSo he did what every kid in 1988 did: he had his friend three-way call her.\n\n\"You know Jack, right?\" his friend asked.\n\n\"Sure, my neighbor,\" Kim said. So far, so good.",
            choices: [],
            autoOutcome: .nextModule(id: "p1_kim_heartbreak")
        ),

        StoryModule(
            id: "p1_kim_heartbreak",
            title: "NOT MY TYPE",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "\"I'm not really into him like that. He's not my type,\" Kim said. \"I'm kind of seeing this guy, Ricky, in 8th grade.\"\n\nJack's heart dropped to the floor along with the phone. It would be years before he'd work up the nerve to try again.",
            choices: [],
            autoOutcome: .nextModule(id: "p1_kickball")
        ),

        StoryModule(
            id: "p1_kickball",
            title: "KICKBALL",
            imageColor: SKColor(red: 0.30, green: 0.55, blue: 0.35, alpha: 1),
            text: "Picking time was Jack's second favorite part of school, right behind finding a lunch seat. Today his team was down 4-3, bases loaded, bottom of the last inning.\n\nAll he needed was a hit. Kim was watching. This was his moment to be the hero.\n\nHe pointed high into the sky. The pitcher laughed and rolled the ball...",
            choices: [],
            autoOutcome: .miniGame(.kickball,
                                   winID: "p1_kickball_dream",
                                   loseID: "p1_kickball_retry")
        ),

        StoryModule(
            id: "p1_kickball_retry",
            title: "NOT LIKE THIS",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Even here, that cocky red orb refuses to cooperate.\n\nBut something about this moment feels... bendable. Like the rules could be different if Jack just tried again.",
            choices: [
                StoryChoice(label: "TRY AGAIN",
                            outcome: .miniGame(.kickball,
                                               winID: "p1_kickball_dream",
                                               loseID: "p1_kickball_retry")),
                StoryChoice(label: "GIVE UP",
                            outcome: .nextModule(id: "p1_kickball"))
            ],
            autoOutcome: .miniGame(.kickball,
                                   winID: "p1_kickball_dream",
                                   loseID: "p1_kickball_retry")
        ),

        StoryModule(
            id: "p1_kickball_dream",
            title: "THE HERO",
            imageColor: SKColor(red: 0.72, green: 0.58, blue: 0.12, alpha: 1),
            text: "The ball rocketed off Jack's foot and sailed over everyone's heads. The bases emptied. Kim was on her feet, cheering his name.\n\nBut as Jack rounded second, the cheering stretched thin and far away. The pavement rippled like water. The sky went soft at the edges.\n\nIt was a dream.",
            choices: [],
            autoOutcome: .nextModule(id: "p1_kickball_vision")
        ),

        StoryModule(
            id: "p1_kickball_vision",
            title: "WHAT ACTUALLY HAPPENED",
            imageColor: SKColor(red: 0.20, green: 0.42, blue: 0.68, alpha: 1),
            text: "Jack woke up on the hot pavement to a ring of staring classmates — and heard what actually happened.\n\nA small pebble altered the ball's course. He missed completely and cracked his head on the ground. And when he got up, armor covered his body. Blue skies. Green hills. An evil ogre on horseback carrying away a gleaming silver sword — HIS sword.\n\n\"Give me back my sword!\" Jack had screamed — chasing a kid named Chad across the parking lot. They never let him forget it.\n\nBut somewhere behind his eyes, that world felt more real than this one.",
            choices: [],
            autoOutcome: .nextModule(id: "p1_billy_badger")
        ),

        StoryModule(
            id: "p1_billy_badger",
            title: "THE SUMMER SCREAM",
            imageColor: SKColor(red: 0.45, green: 0.16, blue: 0.16, alpha: 1),
            text: "The last week of school was pure chaos — bucket races, mop limbo, kids running the halls like the inmates had taken over the asylum.\n\nOne boy made it his personal mission to make Jack's life miserable: Billy Badger. He waited for Jack every day at lunch.\n\n\"Where you gonna sit today?\" Billy sneered. \"What are you going to get?\"",
            choices: [],
            autoOutcome: .nextModule(id: "p1_becky_incident")
        ),

        StoryModule(
            id: "p1_becky_incident",
            title: "THE PUNCH",
            imageColor: SKColor(red: 0.55, green: 0.20, blue: 0.20, alpha: 1),
            text: "Jenny — a family friend's daughter, a year younger — came around the corner just as Billy got in Jack's face again. Jack shoved him back. \"Stop.\"\n\nBilly answered with a fist to the face and ran off laughing, disappearing into a hallway full of cheering kids and an impromptu bucket race.\n\nJack got up, furious. An empty mop bucket rolled to a stop at his feet.\n\nOne foot in. Mop in hand. GO.",
            choices: [],
            autoOutcome: .miniGame(.mopChase,
                                   winID: "p1_chase_crash",
                                   loseID: "p1_chase_retry")
        ),

        StoryModule(
            id: "p1_chase_retry",
            title: "HE'S GETTING AWAY",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Billy slipped out the far doors, cackling.\n\nBut in Jack's memory of that day, the chase always restarts — mop in hand, rage in heart.",
            choices: [
                StoryChoice(label: "TRY AGAIN",
                            outcome: .miniGame(.mopChase,
                                               winID: "p1_chase_crash",
                                               loseID: "p1_chase_retry")),
                StoryChoice(label: "GIVE UP",
                            outcome: .nextModule(id: "p1_becky_incident"))
            ],
            autoOutcome: .miniGame(.mopChase,
                                   winID: "p1_chase_crash",
                                   loseID: "p1_chase_retry")
        ),

        StoryModule(
            id: "p1_chase_crash",
            title: "THE INCIDENT",
            imageColor: SKColor(red: 0.55, green: 0.20, blue: 0.20, alpha: 1),
            text: "Jack was one lunge from Billy's collar when the bucket hit the janitor water.\n\nHe slipped, flying toward the floor, and grabbed the only thing in reach to catch himself: Becky Smith's sweater. It ripped clean off. The hallway erupted. Becky shrieked and ran for the bathroom.\n\nJack stood there, pants soaked in dirty janitor water. He could not have looked worse.\n\nHe had never wanted the school year to end more badly in his life.",
            choices: [],
            autoOutcome: .nextModule(id: "p1_birthday")
        ),

        // ── ACT 1: THE GIFT ─────────────────────────────────────────────────────

        StoryModule(
            id: "p1_birthday",
            title: "A MAGICAL GIFT",
            imageColor: SKColor(red: 0.62, green: 0.45, blue: 0.18, alpha: 1),
            text: "A small, heavy box wrapped in mystical paper sat waiting. \"I think I found your sport,\" Jack's dad said.\n\nInside: four beanbags, two red and two blue. \"Not just beanbags,\" his dad grinned, and led him to the backyard — where two hand-built cornhole boards sat waiting on the lawn.\n\nJack's future was outside. His power would be in the bags.",
            choices: [],
            autoOutcome: .nextModule(id: "p1_tim_intro")
        ),

        StoryModule(
            id: "p1_tim_intro",
            title: "TIM'S CHALLENGE",
            imageColor: SKColor(red: 0.55, green: 0.40, blue: 0.18, alpha: 1),
            text: "His first opponent: his little brother Tim, three years younger and his best buddy. Tim was more athletic than Jack — but he had one legendary weakness, and it doubled as a weapon at close range.\n\nJack took a breath, held it, and got ready to throw past the odor and into the clean, fresh air.",
            choices: [],
            autoOutcome: .miniGame(.cornholeVs(opponent: .tom),
                                   winID: "p1_tim_win",
                                   loseID: "p1_tim_lose")
        ),

        StoryModule(
            id: "p1_tim_lose",
            title: "NOT THIS TIME",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Tim shrieked with delight. Jack's ego took the hit worse than the bag did.\n\nWhat will you do?",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.cornholeVs(opponent: .tom),
                                               winID: "p1_tim_win",
                                               loseID: "p1_tim_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .nextModule(id: "p1_tim_intro"))
            ],
            autoOutcome: .miniGame(.cornholeVs(opponent: .tom),
                                   winID: "p1_tim_win",
                                   loseID: "p1_tim_lose")
        ),

        StoryModule(
            id: "p1_tim_win",
            title: "THIS COULD BE MY GAME",
            imageColor: SKColor(red: 0.30, green: 0.55, blue: 0.35, alpha: 1),
            text: "Jack's bag relished its escape, sailing clean into the hole. Tim shrieked. Jack cheered.\n\nThis could be his game. This could be his future.\n\nSchool was almost out. It was time to race home and start the summer for real.",
            choices: [],
            autoOutcome: .nextModule(id: "p1_last_day")
        ),

        // ── Last day of school — bike race setup ───────────────────────────────
        StoryModule(
            id: "p1_last_day",
            title: "LAST DAY OF SCHOOL",
            imageColor: SKColor(red: 0.55, green: 0.72, blue: 0.30, alpha: 1),
            text: "On the last day of school, Jack, his brother Tim and their friend Jenny raced home on their bikes.\n\nJack made a ridiculous bet: lose the race, lose the new cornhole set. He was confident in his speed.\n\nBut first he had to survive the deadly traffic — and the bean bags thrown by Billy Badger's gang of thugs, lying in wait along the road.",
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
            text: "Jack pedaled faster, dodging cars going 40 and bean bags going 5 — a moving cornhole board in a crazy variation of the game.\n\nTim and Jenny pulled ahead now and then, but Jack saved his energy for the final stretch. Victory!\n\n\"Now let's put that new board through a real tournament,\" Jenny says.",
            choices: [],
            autoOutcome: .spawnOnMap(StorySpawnConfig(
                trigger: StoryManager.triggerCornhole,
                nextModuleID: "p1_jen_intro"))
        ),

        // ── Player approaches cornhole board — Jenny wager ─────────────────────
        StoryModule(
            id: "p1_jen_intro",
            title: "JENNY'S WAGER",
            imageColor: SKColor(red: 0.30, green: 0.55, blue: 0.35, alpha: 1),
            text: "Jenny had never played cornhole before, but she was a decent athlete — softball, mostly — and curious to test her arm.\n\n\"Let's play for something real,\" she says. \"Beat me, and I'll take you to the party some kids are throwing this weekend. Lose, and you're giving up your action figures.\"\n\nHalfway through, Jenny mentions Becky asked about him. Apparently she felt bad about the sweater. Now the pressure was really on.",
            choices: [],
            autoOutcome: .miniGame(.cornholeVs(opponent: .jenny),
                                   winID: "p1_jen_win",
                                   loseID: "p1_jen_lose")
        ),

        // ── Lose to Jenny ────────────────────────────────────────────────────────
        StoryModule(
            id: "p1_jen_lose",
            title: "NOT THIS TIME",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Jenny pulls off the win!\n\n\"Better luck next time,\" she says with a smirk.\n\nWhat will you do?",
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

        // ── Beat Jenny — head for the party ─────────────────────────────────────
        StoryModule(
            id: "p1_jen_win",
            title: "TO THE PARTY",
            imageColor: SKColor(red: 0.25, green: 0.50, blue: 0.68, alpha: 1),
            text: "Jack's bag topped hers, sinking clean in the hole. He was going to the party.\n\n\"It's this weekend, at Stephanie's,\" Jenny says. \"But there's one problem — a river runs right through the shortcut.\"\n\nThey had no boat, and no time to build a real bridge. But they did have sandbags from a recent flood...",
            choices: [],
            autoOutcome: .spawnOnMap(StorySpawnConfig(
                trigger: StoryManager.triggerBridge,
                nextModuleID: "p2_river_arrive"))
        ),

        // ── ACT 2: THE PARTY ─────────────────────────────────────────────────────

        StoryModule(
            id: "p2_river_arrive",
            title: "THE RIVER",
            imageColor: SKColor(red: 0.12, green: 0.28, blue: 0.48, alpha: 1),
            text: "They could have swum across, but throwing sandbags into the water to build a line was a lot more fun — and Jack swore he could see the shapes of piranhas circling below, hungry for anyone too slow to cross.",
            choices: [],
            autoOutcome: .miniGame(.piranha, winID: "p2_river_win", loseID: "p2_river_lose")
        ),

        StoryModule(
            id: "p2_river_lose",
            title: "SWEPT AWAY",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "The current won this round. Try the crossing again?",
            choices: [
                StoryChoice(label: "TRY AGAIN",
                            outcome: .miniGame(.piranha, winID: "p2_river_win", loseID: "p2_river_lose")),
                StoryChoice(label: "STEP BACK",
                            outcome: .spawnOnMap(StorySpawnConfig(
                                trigger: StoryManager.triggerBridge,
                                nextModuleID: "p2_river_arrive")))
            ],
            autoOutcome: .miniGame(.piranha, winID: "p2_river_win", loseID: "p2_river_lose")
        ),

        StoryModule(
            id: "p2_river_win",
            title: "A SECRET ENTRANCE",
            imageColor: SKColor(red: 0.30, green: 0.24, blue: 0.42, alpha: 1),
            text: "Dry(ish) on the other side, Jack and Jenny hiked through the woods and found a secret entrance to the party — guarded by a man in an old, faded football jersey.\n\n\"In order to pass, you must defeat me,\" Herman decreed. He was the high school janitor, and he had never quite let go of his glory days. In the distance, a cornhole board sat over a ledge. A blowtorch flared periodically between the board and the mouth of a waiting dragon.\n\n\"Beat me and defy the dragon fire, and you may proceed.\" Jack looked down at a mountain of beanbags — all soaked in gasoline.",
            choices: [],
            autoOutcome: .spawnOnMap(StorySpawnConfig(
                trigger: StoryManager.triggerCave,
                nextModuleID: "p2_herman_intro"))
        ),

        StoryModule(
            id: "p2_herman_intro",
            title: "HERMAN'S GATE",
            imageColor: SKColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1),
            text: "Jack picked up a soaked bag and flung it through the dragon's flame. It landed on the board and burned it to ash.\n\n\"Sir Michael!\" Herman shouted, and a small boy darted in to swap in a fresh board. The rules here were clearly different.",
            choices: [],
            autoOutcome: .miniGame(.cornholeVs(opponent: .barnum),
                                   winID: "p2_herman_win",
                                   loseID: "p2_herman_lose")
        ),

        StoryModule(
            id: "p2_herman_lose",
            title: "BEATEN BACK",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Herman and his dragon send you packing. Try again?",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.cornholeVs(opponent: .barnum),
                                               winID: "p2_herman_win",
                                               loseID: "p2_herman_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .spawnOnMap(StorySpawnConfig(
                                trigger: StoryManager.triggerCave,
                                nextModuleID: "p2_herman_intro")))
            ],
            autoOutcome: .miniGame(.cornholeVs(opponent: .barnum),
                                   winID: "p2_herman_win",
                                   loseID: "p2_herman_lose")
        ),

        StoryModule(
            id: "p2_herman_win",
            title: "THROUGH THE TUNNEL",
            imageColor: SKColor(red: 0.35, green: 0.24, blue: 0.45, alpha: 1),
            text: "Jack battled to completion and beat the mighty Herman and his vicious dragon. But his greatest challenge was still ahead — the tunnel to the magical realm of a middle school party.\n\nA bonfire roared. A boombox blasted Aerosmith. Dozens of kids danced in the dark.",
            choices: [],
            autoOutcome: .nextModule(id: "p2_party_arrive")
        ),

        StoryModule(
            id: "p2_party_arrive",
            title: "THE PARTY",
            imageColor: SKColor(red: 0.45, green: 0.30, blue: 0.10, alpha: 1),
            text: "Jenny vanished into her group of friends — \"the only way you'll learn to socialize,\" she said. Jack wandered the crowd until he spotted the most beautiful thing in the clearing: a cornhole setup.\n\nRicky Rogers stood in front of the board — the eighth-grade legend every girl had a crush on and every boy wanted to be. \"You wanna play?\" Ricky asked.\n\nBecky stood up beside him. \"Let's make this fun, Jack,\" she said. \"If you beat us, I'll go on a date with you.\"\n\nJack ran to find the only partner he could trust. \"Jenny! I need your help with something.\" The teams formed: Jack vs. Ricky, Jenny vs. Becky.",
            choices: [],
            autoOutcome: .miniGame(.cornholeVs(opponent: .ricky),
                                   winID: "p2_ricky_win",
                                   loseID: "p2_ricky_lose")
        ),

        StoryModule(
            id: "p2_ricky_lose",
            title: "SO CLOSE",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Ricky's arc, his spin — it was a work of art, and it just barely held. Try again?",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.cornholeVs(opponent: .ricky),
                                               winID: "p2_ricky_win",
                                               loseID: "p2_ricky_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .nextModule(id: "p2_party_arrive"))
            ],
            autoOutcome: .miniGame(.cornholeVs(opponent: .ricky),
                                   winID: "p2_ricky_win",
                                   loseID: "p2_ricky_lose")
        ),

        StoryModule(
            id: "p2_ricky_win",
            title: "THE BIGGEST WIN OF HIS LIFE",
            imageColor: SKColor(red: 0.72, green: 0.58, blue: 0.12, alpha: 1),
            text: "Ricky's bag missed the board entirely on the final throw. Jack's bag landed hard and slithered into the hole.\n\n\"Well played,\" Ricky grinned, shaking his hand like it was nothing. Jack shook Becky's hand next. She smiled.\n\n\"Where are you taking me?\" she asked.\n\nJack had no freaking idea.",
            choices: [],
            autoOutcome: .nextModule(id: "p3_carnival_intro")
        ),

        // ── ACT 3: THE DATE ──────────────────────────────────────────────────────

        StoryModule(
            id: "p3_carnival_intro",
            title: "THE CORNHOLE CARNIVAL",
            imageColor: SKColor(red: 0.55, green: 0.30, blue: 0.55, alpha: 1),
            text: "Jenny talked him out of the usual movie-theater date. \"Let her see who you really are,\" she said.\n\nThere was a unique event in town that weekend — a cornhole carnival, where they took the game and turned it on its head in a dozen strange ways. Win three games, and you get a prize.",
            choices: [],
            autoOutcome: .nextModule(id: "p3_baseball_intro")
        ),

        StoryModule(
            id: "p3_baseball_intro",
            title: "BASEBALL CORNHOLE",
            imageColor: SKColor(red: 0.25, green: 0.50, blue: 0.68, alpha: 1),
            text: "Becky had played softball for years and was captain of her middle school team. First up: a baseball challenge using beanbags as balls.\n\nJack imagined himself as a Red Sox legend rewriting history against the Mets. Becky laughed — she actually got his sense of humor.",
            choices: [],
            autoOutcome: .miniGame(.baseballVs(difficulty: .standard),
                                   winID: "p3_baseball_win",
                                   loseID: "p3_baseball_lose")
        ),

        StoryModule(
            id: "p3_baseball_lose",
            title: "STRUCK OUT",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Becky's got the edge this round. Want another shot?",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.baseballVs(difficulty: .standard),
                                               winID: "p3_baseball_win",
                                               loseID: "p3_baseball_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .nextModule(id: "p3_baseball_intro"))
            ],
            autoOutcome: .miniGame(.baseballVs(difficulty: .standard),
                                   winID: "p3_baseball_win",
                                   loseID: "p3_baseball_lose")
        ),

        StoryModule(
            id: "p3_baseball_win",
            title: "KNIGHT OF THE CORNHOLE KINGDOM",
            imageColor: SKColor(red: 0.45, green: 0.28, blue: 0.08, alpha: 1),
            text: "\"I somehow managed to win,\" Jack admits — though Becky may have let him.\n\nNext: medieval times. Jack climbed onto a bike in a suit of cornhole armor, ready to joust with the same bat he'd just used, aiming to land it in his opponent's cornhole.\n\n\"I have to defend her honor,\" he told Becky. \"It's my destiny as a knight of the Cornhole Kingdom.\" He was such a dork. She loved it.",
            choices: [],
            autoOutcome: .miniGame(.jousters, winID: "p3_joust_win", loseID: "p3_joust_lose")
        ),

        StoryModule(
            id: "p3_joust_lose",
            title: "UNHORSED",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "That round didn't go your way. Ride again?",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.jousters, winID: "p3_joust_win", loseID: "p3_joust_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .nextModule(id: "p3_baseball_win"))
            ],
            autoOutcome: .miniGame(.jousters, winID: "p3_joust_win", loseID: "p3_joust_lose")
        ),

        StoryModule(
            id: "p3_joust_win",
            title: "ONE PRIZE AWAY",
            imageColor: SKColor(red: 0.30, green: 0.55, blue: 0.35, alpha: 1),
            text: "After some rough rides, Jack struck his opponent down. Beaten and sweaty, but one prize away from total victory.\n\n\"I have to admit,\" Becky said, grabbing his shoulder and pulling him close, \"I've never had this much fun. This place is amazing!\"\n\n\"What do you want to play next?\" Jack asked.\n\n\"Horse race!\" she shouted, already running for it.",
            choices: [],
            autoOutcome: .miniGame(.horseRace, winID: "p3_horserace_win", loseID: "p3_horserace_lose")
        ),

        StoryModule(
            id: "p3_horserace_lose",
            title: "FALLING BEHIND",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Your horse just couldn't keep up. Run it back?",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.horseRace, winID: "p3_horserace_win", loseID: "p3_horserace_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .nextModule(id: "p3_joust_win"))
            ],
            autoOutcome: .miniGame(.horseRace, winID: "p3_horserace_win", loseID: "p3_horserace_lose")
        ),

        StoryModule(
            id: "p3_horserace_win",
            title: "THE GRAND PRIZE",
            imageColor: SKColor(red: 0.72, green: 0.58, blue: 0.12, alpha: 1),
            text: "Speed and accuracy — and at that moment, Jack was perfect. Nothing could stop his momentum.\n\nThe grand prize: a floatable cornhole set, just in time for pool season. Swimming would never be the same.\n\nJack walked Becky to her mom's car. \"I had a great time. Give me a call sometime!\" She wrote her number on his hand in pen. \"It's unlisted,\" she said, and kissed him on the cheek before running off.\n\nThe most incredible night of Jack's life so far had just ended, and he was never happier.",
            choices: [],
            autoOutcome: .nextModule(id: "p4_pool_intro")
        ),

        // ── ACT 4: TIME FOR TIM ──────────────────────────────────────────────────

        StoryModule(
            id: "p4_pool_intro",
            title: "TIME FOR TIM",
            imageColor: SKColor(red: 0.20, green: 0.55, blue: 0.70, alpha: 1),
            text: "Jack woke up glowing. Downstairs, Tim and his friends were already inflating the new floating cornhole set in the pool, water guns blasting, everyone pretending to be superheroes or wrestlers.\n\n\"I bet you can't beat me,\" Tim chimed in. \"If I beat you, can I use the pool tonight?\"\n\n\"Why? Who are you having over?\" Jack asked.\n\n\"None of your business,\" Tim shot back.",
            choices: [],
            autoOutcome: .miniGame(.beachball, winID: "p4_pool_win", loseID: "p4_pool_lose")
        ),

        StoryModule(
            id: "p4_pool_lose",
            title: "OUTPLAYED",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "Tim put up a real challenge. Dive back in?",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.beachball, winID: "p4_pool_win", loseID: "p4_pool_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .nextModule(id: "p4_pool_intro"))
            ],
            autoOutcome: .miniGame(.beachball, winID: "p4_pool_win", loseID: "p4_pool_lose")
        ),

        StoryModule(
            id: "p4_pool_win",
            title: "THE NUMBER",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.45, alpha: 1),
            text: "Jack won, using an imaginary creature — an inflatable dolphin someone's friend had brought — as a bonus mechanism the whole time.\n\nThen he looked down at his hand. The pool water had washed off half of Becky's number. Panic set in — her number was unlisted, and he didn't know any of her friends.\n\n\"Tim, I don't think you understand what just happened,\" he said, staring at his hand.",
            choices: [],
            autoOutcome: .nextModule(id: "p4_confession")
        ),

        StoryModule(
            id: "p4_confession",
            title: "THE GREAT TREE",
            imageColor: SKColor(red: 0.30, green: 0.45, blue: 0.20, alpha: 1),
            text: "\"Whose number was that?\" Tim asked. \"I tried calling it, but some girl picked up.\"\n\n\"You WHAT? Why did you call it?!\" Jack shouted.\n\n\"I was curious,\" Tim shrugged. \"Do you still have the number?\"\n\n\"I buried it,\" Tim said. \"In the woods, by the Great Tree. Just in case I needed it again.\"\n\n\"Where did you bury it?\" Jack demanded.\n\n\"By the Great Tree,\" Tim said. \"But you'll need to beat the Fairy Queen to get it back.\"",
            choices: [],
            autoOutcome: .spawnOnMap(StorySpawnConfig(
                trigger: StoryManager.triggerAppleTree,
                nextModuleID: "p4_queen_intro",
                flags: [.dogsEnabled, .bulliesEnabled]))
        ),

        StoryModule(
            id: "p4_queen_intro",
            title: "THE FAIRY QUEEN",
            imageColor: SKColor(red: 0.18, green: 0.32, blue: 0.58, alpha: 1),
            text: "And so the quest began. The Fairy Queen guarding the Great Tree used magic bags that destroyed everything they touched — Jack would need every special bag he'd gathered to stand a chance.\n\nMeanwhile the yard had been taken over by stray dogs, and Billy Badger's gang was still looking for a rematch. The world had gotten a little more dangerous. Good thing Jack still had his arms, and his bean bags.",
            choices: [],
            autoOutcome: .miniGame(.cornholeVs(opponent: .spirit),
                                   winID: "p4_queen_win",
                                   loseID: "p4_queen_lose")
        ),

        StoryModule(
            id: "p4_queen_lose",
            title: "NOT YET",
            imageColor: SKColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1),
            text: "The Fairy Queen's magic proves too much. Special bags may help against such a foe... try again when ready.",
            choices: [
                StoryChoice(label: "REMATCH",
                            outcome: .miniGame(.cornholeVs(opponent: .spirit),
                                               winID: "p4_queen_win",
                                               loseID: "p4_queen_lose")),
                StoryChoice(label: "QUIT",
                            outcome: .spawnOnMap(StorySpawnConfig(
                                trigger: StoryManager.triggerAppleTree,
                                nextModuleID: "p4_queen_intro")))
            ],
            autoOutcome: .miniGame(.cornholeVs(opponent: .spirit),
                                   winID: "p4_queen_win",
                                   loseID: "p4_queen_lose")
        ),

        StoryModule(
            id: "p4_queen_win",
            title: "THE FAIRY QUEEN YIELDS",
            imageColor: SKColor(red: 0.30, green: 0.55, blue: 0.35, alpha: 1),
            text: "The Fairy Queen's last magic bag fizzled out against Jack's own. She bowed her leafy crown and stepped aside from the Great Tree.\n\nThe quest was won. Now to dig up what was buried.",
            choices: [],
            autoOutcome: .nextModule(id: "p4_ending")
        ),

        StoryModule(
            id: "p4_ending",
            title: "THE CALL",
            imageColor: SKColor(red: 0.72, green: 0.58, blue: 0.12, alpha: 1),
            text: "The Fairy Queen yielded, and Jack dug up the rest of Becky's number by the roots of the Great Tree.\n\nHe ran home, sat down in front of the phone, and dialed. Whatever came next, he was never washing this hand again.\n\n— END OF PART 1 —",
            choices: [],
            autoOutcome: .spawnOnMap(StorySpawnConfig(nextModuleID: "p4_ending"))
        ),
    ]
}
