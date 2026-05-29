# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is an Xcode iOS project. All building and testing goes through Xcode or `xcodebuild`.

```bash
# Build (simulator)
xcodebuild -project CornholeKings88.xcodeproj -scheme CornholeKings88 -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run unit tests
xcodebuild -project CornholeKings88.xcodeproj -scheme CornholeKings88 -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run a single test method
xcodebuild -project CornholeKings88.xcodeproj -scheme CornholeKings88 -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:CornholeKings88Tests/CornholeKings88Tests/example
```

The easiest way to run and iterate is to open `CornholeKings88.xcodeproj` in Xcode and use ⌘R / ⌘U.

## Architecture Overview

The game is a top-down 2D RPG-style iOS app built with **SpriteKit** and **UIKit**. It follows an NES Zelda screen-by-screen scrolling pattern with mini-game overlays.

### Scene Graph

```
GameViewController (UIViewController)
└── SKView
    └── GameScene (SKScene, root)
        ├── gameWorld (SKNode) — all world content lives here
        │   ├── TMXMap.mapNode — tiled map layers (SKNodes)
        │   └── PlayerNode (SKSpriteNode)
        └── cameraNode (SKCameraNode) — controls viewport
```

Mini-games replace the active scene entirely and return to `GameScene` via `previousScene` + `onComplete`:
- `CornholeMiniGameScene` — cornhole bag-toss mini-game
- `CornholeBaseballScene` — beanbag baseball mini-game with a SwiftUI HUD overlay

The main menu flow also branches to non-game scenes:
- `StoryModuleScene` — story chapter viewer (launched from PLAY)
- `MiniGamePickerScene` — mini-game selection (launched from MINI GAMES)
- `StatsScene` — player stats screen (launched from STATS)
- `SettingsScene` — settings screen (launched from SETTINGS); includes a "reset tutorials" action backed by `TutorialManager.resetAll()`
- `BeachBallCornholeScene` — pool beachball cornhole blitz (launched from MINI GAMES or pool world trigger)

### Coordinate System & Pixel Scaling

`GameViewController` computes an integer zoom factor `n` so that every source pixel maps to exactly `n` device pixels. The resulting scene size in source pixels is passed to `GameScene`. Inside `GameScene`, `worldZoom = 2.0` is applied to the camera scale (`cameraNode.setScale(1.0 / worldZoom)`), making tiles appear at 2× inside the already-scaled scene. The map is authored at 8×8 tile size; the rendered tile size on screen is `8 × n × worldZoom` device pixels.

The visible play area is a square "stage" (`stageSize = scene.width`). Chrome bars above and below the stage hold the HUD (hearts/score) and on-screen controls (D-pad + A/B buttons). `stageWorldSize = stageSize / worldZoom` is the number of world units in one navigable screen.

### Map System

Maps are authored in **Tiled** (.tmx format, CSV encoding) and loaded by `TMXLoader`. The loader:
1. Parses the `.tmx` XML to find tileset references and layer data.
2. Resolves each `.tsx` tileset to its PNG by lowercasing the basename (e.g., `Grass.tsx` → `grass.png`). **Both the .tmx and all PNG files must be in the Xcode target's Copy Bundle Resources phase**; `.tsx` files are not needed at runtime.
3. Builds `SKSpriteNode` tiles for each layer, returned as a `TMXMap` struct containing:
   - `layerGIDs` — raw GID grid per layer name
   - `layerNodes` — rendered `SKNode` per layer
   - `tilesetRanges: [(name: String, gidRange: ClosedRange<Int>)]` — every loaded tileset's lowercased basename and its assigned GID range

`GameScene` uses `tilesetRanges` to detect special tiles **by tileset name** (case-insensitive `contains`), not by hardcoded GID ranges. This means adding a new tileset in Tiled never requires touching code as long as the name contains the expected keyword. Detection mapping:

| Tileset name contains | Triggers |
|-----------------------|----------|
| `cornhole`            | Classic cornhole mini-game (board tiles are 2×2 groups) |
| `baseball`            | Beanbag baseball mini-game |
| `tree` (but not `apple`) | Tree climbing (safe zone) |
| `apple`               | Apple tree → cornhole vs. Tree Spirit |
| `bee`                 | Beehive battle mini-game |
| `pool`                | Beach-ball cornhole |
| `bridge_stone`        | Beach-ball cornhole (same mini-game, different trigger) |
| `chest`               | Open chest → 50/50 heart refill or dog biscuit |
| `bridge_wood`         | Piranha mini-game; on win, unlocks walkable bridge (ImaginationFX layer) |

The **`"fences"` layer** (by layer name, not tileset name) is also scanned — any non-zero tile triggers `SuburbanJoustersScene` on A-press. See **Suburban Jousters** below.

Collision tiles still come from the `Collisions` layer (any non-zero GID); water collisions still come from explicit GID ranges in `buildPhysics(from:)`.

### Physics

- `PlayerNode` uses a small circle physics body anchored at the sprite's feet (`center: CGPoint(x: 0, y: -16)`).
- Collision tiles (water, walls) get `SKPhysicsBody(rectangleOf: tileSize)` bodies added in `buildPhysics(from:)`, using `WorldBit` for collision.
- Mini-game scenes run their own hand-rolled physics (bag arc, gravity, board bounce) without using SpriteKit's physics engine.
- Physics category bits: `categoryBit = 0x1 << 0` (player), `worldBit = 0x1 << 1` (terrain), `collectibleBit = 0x1 << 2` (items), `enemyBit = 0x1 << 3` (enemies). When the player is in a tree, `enemyBit` is removed from their collision and contact masks so enemies pass through.

### Player Animation

`PlayerNode` slices a sprite sheet (`player.png`, 48×48 frames, 6 columns × 10 rows) into animation frame arrays keyed by `AnimState` × `Facing`. Left-facing frames are produced by mirroring right-facing frames via `xScale = -1`. z-position is set to `-position.y` each frame for painter's-algorithm depth sorting.

### Tree Climbing

Press A near a tree tile to climb it. While in a tree the player is stationary and safe from enemies (`enemyBit` removed from physics masks). A green leaf canopy is drawn over the player as a visual indicator. Press A again to descend, or use the d-pad — any directional input auto-descends and resumes normal movement. Walking out of tree proximity also auto-descends.

The proximity radius is 20 world units (`treeRadius` in `checkBoardProximity()`). Tree tiles are detected by tileset name — any tileset whose lowercased basename contains `"tree"` and does **not** contain `"apple"` is treated as climbable (e.g. `Big_Oak_Tree.tsx`, `Medium_Spruce_Tree.tsx`, `Big_Birch_Tree.tsx`). The `▲A` prompt appears when in range.

### Apple Tree

Tilesets whose name contains `"apple"` (e.g. `Apple_Tree.tsx`) are detected separately by `extractAppleTreePositions(from:)` and excluded from climbing detection. Walking near one and pressing A launches `CornholeMiniGameScene` with `preSelectedOpponent = .spirit`, skipping the opponent picker. The interaction radius is 26 world units.

### Bridge Stone

Tilesets whose name contains `"bridge_stone"` (e.g. `Bridge_Stone_Vertical.tsx`) launch the beach-ball cornhole mini-game when the player presses A nearby. Interaction radius is 36 world units. Same entry path as the pool tile trigger.

### Chest

Tilesets whose name contains `"chest"` (e.g. `Golden_Chest_Anim.tsx`) become one-time interactable rewards. On A-press:
1. The chest's tile sprite is hidden in every layer at that world position (`hideChestTile(at:)`).
2. A 50/50 roll grants either `HeartsManager.shared.gain()` or `inventory.collect(.dogBiscuit, count: 1)`.
3. A floating `+ HEART` / `+ DOG BISCUIT` pickup label animates from the chest.
4. The opened position is tracked in `openedChestKeys: Set<String>` (key = `"<intX>,<intY>"`) so proximity detection skips it for the rest of the session. Memory is **not** persisted to `UserDefaults`.

### Bridge Wood

Tilesets whose name contains `"bridge_wood"` (e.g. `Bridge_Wood.tsx`) trigger `BridgePiranhaScene` when the player presses A nearby (36-unit radius). The prompt is suppressed once the bridge is unlocked.

On win, `unlockBridge()` runs:
1. Sets `UserDefaults` key `"bridgeUnlocked_v1"` to `true` — persists across launches.
2. Shows the `ImaginationFX` map layer (hidden by default; contains the visual bridge tiles over the river).
3. Removes the cached water-collision physics bodies (`bridgePhysicsNodes`) that sit under those tiles, making the river crossable.

On scene load, GameScene checks the flag and calls `unlockBridge()` immediately after `cacheBridgePhysicsNodes(from:)` so already-unlocked sessions see the bridge from the start.

### Mini-Game Pattern

Both mini-games follow the same contract:
```swift
var previousScene: SKScene?
var onComplete: ((Bool) -> Void)?
```
`GameScene` sets both before presenting the mini-game. The mini-game calls `onComplete?(won)` when finished, and `GameScene`'s closure re-presents itself. `hasSetup` in `GameScene` prevents double-initialization when the scene is re-presented after a mini-game returns.

`CornholeBaseballScene` additionally injects a SwiftUI `BaseballHUDView` as a `UIHostingController` onto the host `SKView` in `didMove(to:)` and removes it in `willMove(from:)`.

`CornholeMiniGameScene` calls `CornholeStatsManager.shared.recordCornhole()` each time any bag enters the hole, and `recordWin()`/`recordLoss()` in `dismissScene(playerWon:)` before calling `onComplete`. This covers both in-world cornhole boards and the mini-games picker path.

### Cornhole Opponents

`CornholeMiniGameScene` supports four opponents selected via `OpponentPickerNode` before the game starts. The host scene can bypass the picker by setting `mini.preSelectedOpponent = .spirit` (etc.) before presenting — used by the apple tree world trigger to drop the player straight into a Tree Spirit match.

| Opponent | Enum | Win score | Special rules |
|----------|------|-----------|---------------|
| Tom | `.tom` | 11 | Baseline AI, moderate accuracy |
| Jenny | `.jenny` | 11 | Slightly tighter aim than Tom |
| Billy the Bully | `.billy` | 21 | Forced thunderstorm every round; adaptive difficulty; can throw bomb bags (~25% chance) |
| Tree Spirit | `.spirit` | 21 | Drops magic bags vertically from above (50% cornhole / 50% random board position) |

**Billy adaptive difficulty** — `billyNoiseFactor` starts from career cornhole accuracy (`cornholes / (totalGames × 12)`, clamped to `[1.4, 3.8]`). Each round the player wins tightens Billy by `−0.12`; each round Billy wins eases him by `+0.15`. Range stays within `[1.4, 3.8]`.

**Tree Spirit drop mechanic** — `dropMagicBagFromAbove(targetX:targetY:)` places a `MiniGameBag(isMagic: true)` at `bz = 220` with zero `vx/vy`; existing bz-guard in `resolveBagCollisions()` prevents mid-air collisions. The magic bag falls straight down to its target.

**Bag destruction** — `destroyBag(_:)` sets `isDestroyed = true` and plays a scale/fade animation. Destroyed bags are skipped in `calculateRoundScore()` but stay in `activeBags` until round cleanup. `resolveBagCollisions()` skips destroyed bags.

**Rewards** — beating Billy awards 3 bomb bags; beating the Tree Spirit awards 3 magic bags. These are added to `InventoryManager` via `bombBagsEarned` / `magicBagsEarned` in `dismissScene`.

### Opponent Picker Layout

`OpponentPickerNode` renders opponents in one of three layouts based on count:
- **2 opponents** — side-by-side cards
- **3 opponents** — 2 regular cards on top row, 1 boss card centered below
- **4 opponents** — 2×2 grid: top row regular (Tom, Jenny), bottom row boss (Billy, Spirit) with red borders and `★ BOSS ★` badge

### Audio

`CornholeMiniGameScene` warm-up list (fired at scene load, volume 0, to seed AVAudioEngine):
`hit.mp3`, `hole_score.wav`, `round_end.wav`, `rain_start.wav`, `gopher_pop.wav`, `gopher_steal.wav`, `game_win.wav`, `game_lose.wav`, `storm.mp3`

- **`hit.mp3`** — plays via `SKAction.playSoundFileNamed` each time a bag first touches the board (`bag.hasLanded` transition).
- **`storm.mp3`** — looping `SKAudioNode` (`stormAudioNode`); fades in (1.2 s) when the storm activates, fades out (1.5 s) and removes itself when the storm deactivates.

`LoadingScene.prewarmAudio()` pre-decodes all audio files (both `.wav` and `.mp3`) via `AVAudioPlayer.prepareToPlay()` and seeds SpriteKit's cache via silent `SKAudioNode` instances. Filenames include their extension so the loader can handle mixed formats.

### Stats System

**`CornholeStatsManager.swift`** — singleton that persists cornhole game stats to `UserDefaults`:
- `wins`, `losses`, `cornholes` (total bags through the hole, any owner)
- `defeatedTom`, `defeatedJenny` (cornhole wins) — combined as `baseballUnlocked`
- `defeatedJenBaseball`, `defeatedTomBaseball` (baseball wins) — combined as `joustersUnlocked`
- `currentRank: String` — returns `"Rookie"` (rank progression system TBD)
- `recordWin()`, `recordLoss()`, `recordCornhole()`, `reset()`

**`StatsScene.swift`** — SpriteKit scene accessible from `MainMenuScene` via the STATS button. Matches the main menu aesthetic (dark background, wood plaque header, iron-panel stat cards, ember particles, CRT overlay). Displays:
- **RECORD** — `W - L` wins and losses
- **CORNHOLES** — lifetime bags through the hole
- **RANK** — current rank string

Navigation: `◄ BACK` strip at top (push-down transition back to `MainMenuScene`). Dim `RESET STATS` in the footer resets all stats and re-presents the scene with updated values.

### Inventory System

Items scattered in the world can be walked over to collect them. The system has four files:

- **`Item.swift`** — `ItemType` enum (`coin`, `bag`, `star`, `honeyBag`, `bombBag`, `magicBag`, `fireBag`, `goldenBag`, `dogBiscuit`, `goldenLance`) with `color`, `displayName`, and `hudSymbol`.
- **`InventoryManager.swift`** — holds `[ItemType: Int]` counts; fires an `onChanged` closure when any item is collected. `GameScene` owns the instance.
- **`CollectibleNode.swift`** — `SKNode` subclass placed in the map's `mapNode`. Draws an 8×8 colored tile + glow ring, bobs gently, and pops/fades out on contact. Physics body is a sensor (`collisionBitMask = 0`, `contactTestBitMask = PlayerNode.categoryBit`). Uses `collectibleBit = 0x1 << 2`.
- **`InventoryHUDNode.swift`** — `SKNode` attached to `cameraNode`. Renders a horizontal row of dark pill slots (colored icon + `×N` count label) in the bottom chrome, vertically centered between the top of the D-pad cross and the stage bottom border. Call `refresh(counts:)` to redraw. Each slot container is named `"slot_<rawValue>"` (e.g. `"slot_dogBiscuit"`); `GameScene.handleTouchBegan` walks `nodes(at:)` for that prefix and routes the tap to `handleInventoryTap(_:)` for per-item world-use actions.

**Collection flow in `GameScene`:**
1. `setupPlayer()` ORs `CollectibleNode.collectibleBit` into the player's `contactTestBitMask`.
2. `spawnCollectibles(in:)` drops items around the player's spawn point after the map loads.
3. `didBegin(_:)` detects the contact, calls `item.collect()`, updates `InventoryManager`, and spawns a floating `+NAME` pickup label via `showPickupText(_:at:)`.

**Special bag items** (earned from boss opponents, usable in any cornhole game):
- **`honeyBag`** — immune to wind and bot knockback; sticks on board contact.
- **`bombBag`** — landing on the board destroys all opponent board bags; landing in the hole destroys all opponent hole bags. Billy can also throw bomb bags (~25% chance). Awarded (3) by beating Billy the Bully.
- **`magicBag`** — physically intercepts opponent board bags on collision (opponent bag destroyed, magic bag keeps moving). Scoring in the hole destroys all opponent bags already scored in the hole this round. Awarded (3) by beating the Tree Spirit.
- **`fireBag`** — landing on the board burns all other board bags instantly (thrower keeps 1 pt, all others score 0); subsequent bags landing on the board that round are also destroyed. Sets `boardOnFire = true` until round reset. Landing in the hole burns all other cornholes scored that round by either player (thrower keeps 3 pts, all others score 0). Sets `holeFire = true`. Visuals: pulsing red-orange board overlay + rising ember particles + blinking "🔥 BOARD ON FIRE! 🔥" label. Reward source TBD.

`GameScene` passes `availableBombBags` / `availableMagicBags` / `availableFireBags` into `CornholeMiniGameScene` before presenting it, then deducts used counts and adds earned counts in the `onComplete` closure. `MiniGamePickerScene` reads the same `InventoryManager` (via a local instance) when launching cornhole directly from the picker.

**World-use items** (placed in the open world by tapping the inventory slot):
- **`dogBiscuit`** — earned from chests (50/50 with heart refill). Tapping the inventory slot calls `placeDogBiscuit()`, which decrements the count and spawns a bone-shaped `SKNode` at `player.position` (added to `map.mapNode`, tracked in `placedBiscuits: [PlacedBiscuit]`). In `updateDogs(dt:)`, any non-fleeing dog without a `biscuitTarget` checks for an unclaimed biscuit within an 80-unit sniff radius; first match wins and is claimed. The dog walks to the biscuit, eats for 3 seconds (`eatDuration` in `DogNode`), then `onFinishedEating` fires — the biscuit node pops/fades out and is removed from `placedBiscuits`. After eating, the dog resumes chasing the player.

**Permanent unlock items** (not consumed; awarded once and persist via `UserDefaults`):
- **`goldenLance`** — awarded on first Suburban Jousters win (key `"goldenLanceEarned_v1"`). Reveals the `btnLance` action button in the world HUD. Used to interact with high objects in the world (TBD). The button is a dark gold-bordered circle drawn by `makeLanceButtonContent()` — a diagonal gold shaft, bright tip, and grip wrap.

**Fire bag round state** — reset at the start of each round in `startRound()`: `boardOnFire`, `holeFire`, `fireBoardOverlay`, `fireBoardEmitter` node (named `"fireBoardEmitter"`), and `fireBoardLabel` node (named `"fireBoardLabel"`).

**Losing to the Tree Spirit** — the game-over panel shows a green hint: *"SPECIAL BAGS MAY HELP AGAINST SUCH A FOE..."* to guide the player toward using magic/fire bags.

**To add more item types:** add a case to `ItemType`, give it a `color`/`displayName`/`hudSymbol`, and drop `CollectibleNode(type: .newType)` nodes in `spawnCollectibles(in:)`. If the item should be usable from the inventory HUD, add a case to `GameScene.handleInventoryTap(_:)` for its world-use action.

### Hearts System

`HeartsManager.shared` (singleton, `HeartsManager.swift`) owns a single universal heart count across the world map and every mini-game. Persisted to `UserDefaults` key `"universalHearts_v1"`; max is `5`.

- API: `currentHearts`, `lose()`, `gain()`, `set(_:)`, `refill()`, plus an `onChanged` closure for HUD sync while a modal mini-game (bike race) is up.
- **Hearts drain in:** BikeDodgeScene (crashes / bag hits), BeeHiveScene (bee stings — synced back to `HeartsManager` via `remainingHearts`), and GameScene (enemy bite). Score-based games (cornhole, baseball, beachball) don't drain the universal count.
- **Hearts refill on:** cold app launch (`LoadingScene.didMove`), world-map game over (`GameScene.triggerGameOver`), in-game pickups (`PickupData.heart` in bike race), and on **replay-after-loss** in any heart-draining game (`BikeDodgeScene.resetGame`, `BeeHiveScene.restartGame`). A 0-hearts guard on entry into the bike race and beehive (both from world and picker paths) also refills, so players can't enter a heart-draining game with 0 hearts.
- **Mini-game entry:** heart-draining scenes start with `HeartsManager.shared.currentHearts` (may be less than max if the player took damage earlier in the session). They do not reset to max on entry — only on replay-after-loss.
- `GameScene` registers `HeartsManager.shared.onChanged` in `didMove(to:)` so its HUD redraws when the bike-race modal updates the count off-screen, then calls `resyncHeartsDisplay()` on any return path.

### Tutorial System

Centralized framework that every mini-game uses for consistent first-play onboarding.

- **`TutorialManager.swift`** — singleton tracking which tutorials have been seen (`UserDefaults`). Static keys per game: `.bike`, `.cornhole`, `.baseball`, `.beehive`, `.beachball`, `.piranha`, `.jousters`, `.wellFlinger`; `allKeys` lists them all. API: `hasSeen(_:)`, `markSeen(_:)`, `reset(_:)`, and `resetAll()` (clears every key — used by `SettingsScene`).
- **`TutorialOverlay.swift`** — full-screen `SKNode` overlay with shared styling (wood-iron panel, gold trim, `PressStart2P` font, pulsing prompt). Pass a `[TutorialStep]` and an `onComplete`; tap-to-advance, no skip. Step kinds:
  - `.card(title:body:)` — centered modal.
  - `.hint(at:title:body:)` — panel offset from a target point with a pulsing arrow.
  - Auto text-wrapping; step counter (`1 / 3`); blocks underlying input via host-scene routing (see below).
- **`TutorialHelpButton`** (in `TutorialOverlay.swift`) — reusable `?` button factory. Each mini-game's HUD adds one; `wasTapped(_:)` walks up the parent chain so taps on the icon or its background both register.

**Host-routed input pattern** — `SKNode` has no frame, so `isUserInteractionEnabled = true` alone won't intercept touches. Every host scene's `touchesBegan` runs these two checks first:

```swift
if let overlay = TutorialOverlay.active(in: self) { overlay.advance(); return }
for n in nodes(at: loc) where TutorialHelpButton.wasTapped(n) {
    presentTutorial(autoTriggered: false); return
}
```

**Auto-trigger contract** — each scene's `didMove` (or post-picker entry point for cornhole) checks `TutorialManager.shared.hasSeen(...)` and either starts the game or calls `presentTutorial(autoTriggered: true)`. On completion the scene marks the key seen and kicks off the normal start path (`startGame()`, `startRound()`, `startCountdown()`, `startUserBatting(showModal: false)`, etc.). Replays via the HUD `?` button pass `autoTriggered: false` so no game-state side effects fire.

**To add a tutorial to a new mini-game:**
1. Add a `static let foo = "tutorial.foo.v1"` key to `TutorialManager`.
2. Implement `private func presentTutorial(autoTriggered: Bool)` on the scene with 3 steps (goal + controls + key mechanic).
3. Gate the start path on `TutorialManager.shared.hasSeen(.foo)` in `didMove`.
4. Add the help button to the HUD with `TutorialHelpButton.make()`.
5. Add the routing block above to `touchesBegan`.

### Key Constants

| Symbol | File | Value | Meaning |
|--------|------|-------|---------|
| `worldZoom` | GameScene | 2.0 | Camera zoom multiplier |
| `moveSpeed` | PlayerNode | 120.0 | Player world-units per second |
| `totalCycles` / `pitchesPerHalf` | CornholeBaseballScene | 3 / 3 | Baseball game length |
| `eatDuration` | DogNode | 3.0 | Seconds a dog spends eating a placed biscuit |
| `collectibleBit` | CollectibleNode | `0x1 << 2` | Physics category for collectible items |
| `enemyBit` | PlayerNode | `0x1 << 3` | Physics category reserved for enemies |
| `batWorldPosition` | StoryManager | `CGPoint(x:380, y:260)` | World position of story bat pickup — tune to map |
| `storyBatRadius` | GameScene | 28 | Proximity radius for story bat A-press |

Hardcoded GID ranges for world-trigger tiles are gone — see the "tileset name contains" table in the **Map System** section above for the current detection contract.

### Suburban Jousters

`SuburbanJoustersScene` is a backyard bicycle jousting mini-game. The player rides the left lane; an AI rival descends the right lane. Dual-zone touch: left half pedals/slides shield, right half sweeps lance aim. Heart-draining: each crash costs a heart; first to drop the rival's 3 lives wins.

**World trigger** — any non-zero tile on the `"fences"` map layer (detected by layer name, not tileset name). Pressing A within 36 world units opens the scene via `openSuburbanJousters()`.

**Gate — must beat Jen and Tom at baseball first.** `CornholeStatsManager.shared.joustersUnlocked` (`defeatedJenBaseball && defeatedTomBaseball`) controls access:
- Neither beaten → hint: *"In order to joust on your bike, you need something to use as a lance."*
- Only Jen beaten → hint: *"Beat Tom at baseball to unlock the joust."*
- Both beaten → scene launches.

**Baseball sequencing** — `openCornholeBaseball()` in `GameScene` automatically sets the correct AI difficulty based on progress:
1. First visit: `aiDifficulty = .powerHitter` (Jen). Win sets `defeatedJenBaseball`.
2. Second visit: `aiDifficulty = .greatFielder` (Tom). Win sets `defeatedTomBaseball` and shows the *"The joust awaits!"* banner.
3. Subsequent visits: default `.standard` difficulty (free play).

**Reward** — winning Suburban Jousters for the first time awards the **Golden Lance** (`UserDefaults` key `"goldenLanceEarned_v1"`), reveals `btnLance` in the world HUD, and shows *"You won the Golden Lance!"* banner. Hearts are synced back to `HeartsManager` from `joust.remainingHearts` on exit (win or loss).

**Entry points:**
- `MiniGamePickerScene` → `"jousters"` card (no gate; always accessible from picker)
- World trigger — `"fences"` layer A-press (gated by `joustersUnlocked`)

**Difficulty ramp** — `SuburbanJoustersScene` tracks a global fight count in `UserDefaults` key `"joustersFightCount_v1"`. Speed scales up with repeated plays.

### BeachBall Cornhole

`BeachBallCornholeScene` is a simultaneous 2-minute blitz where player and AI each throw
classic striped beachballs at a floating, drifting cornhole board in a pool.

**Key differences from `CornholeMiniGameScene`:**
- **Timer-based** (2:00 countdown) instead of turn-based (first to 11)
- **Simultaneous play** — both player and AI have independent 2-second throw cooldowns; no turns
- **Beachball physics** — balls bounce off the board surface (`boardRestitution = 0.80`) rather than landing; only the hole scores
- **Board drift** — `boardDriftX` shifts left-right with slow randomized speed; hole position tracks it via `holeCenterX`
- **AI behavior** — throws reactively (0.25–0.85 s after player throws) and autonomously (every ~2 s); accuracy rubber-bands based on score gap
- **Scoring** — 1 pt per cornhole only; board surface is worth 0 pts; winner is player with most cornholes at the buzzer
- **bz visual scale** — uses `bzVisualScale = 0.35` (vs beanbag 0.50) to keep arc arcs on-screen given the identical arc physics

**Entry points:**
- `MiniGamePickerScene` → `"beachball"` card
- World trigger — walk near any tile from a tileset whose name contains `"pool"` or `"bridge_stone"` (e.g. `Bridge_Stone_Vertical.tsx`) and press A.

**Beachball texture** is drawn programmatically in `BeachBallCornholeScene.makeBeachBallTexture(diameter:)` — no image asset needed.

### Well Flinger

`WellFlingerScene` (internally "Well Dropper") is a **fully physics-driven** side-view well descent. The bag falls down a vertical brick shaft under SpriteKit gravity; the player taps to drop small rocks that the bag **bounces off**, steering it past spider webs toward a side-view cornhole board at the bottom. The camera follows the bag down. 3 bags per game; 3 pts hole / 1 pt board / 0 pts for a miss, a web catch, or getting stuck. `winThreshold = 3`.

**World coordinates** — plain SK coordinates (center origin, y-up); there is **no** virtual-grid system. The bag spawns near the top (`y ≈ -H*0.15`) and falls toward `boardCenterY` (a large negative Y at the bottom of the `shaftHeight`-tall shaft). `worldNode` holds all world content; `camNode` follows the bag (clamped so the final landing stays on screen).

**State machine** — `enum TurnState { case falling, settling, ended }`. The whole game runs on real physics; there are no descent/approach/zoom phases. A turn begins in `.falling` (`startTurn()` makes the bag dynamic), and `endTurn(pts:msg:)` moves it to `.ended`, shows a toast, then either starts the next bag or shows the end panel.

**Pipeline (per bag):**
1. `startTurn()` — repositions the bag near the top, makes its body dynamic, and gives it a small downward velocity. `turnState = .falling`.
2. **Fall + steer** — gravity pulls the bag down the shaft. The player taps (`placePlayerRock(at:)`) to drop static warm-tinted rocks (`stoneCat`, `restitution 0.55`) that the bag bounces off. Rock placement is rejected on top of the bag, in the board/ground zone, or above the visible shaft top, and the tap X is clamped to keep at least a bag-width of clearance (`bagSize * 1.4 + 6`, plus the rock radius) from each wall so a rock can't wedge the bag in a wall pocket. Tapping an existing player rock **removes** it instead of placing a new one (`placedRockHit(at:)` finds the nearest within `shaftHalfW * 0.18`; `removePlacedRock(_:)` pops it out). The `update()` loop caps fall speed (180) and lateral speed (160).
3. **Stuck detection** — `update()` tracks downward *progress* (not velocity); if the bag fails to descend `stuckProgressEps` (4) pts for `stuckLimit` (2.0) s it ends the turn with "BAG STUCK!" (0 pts).
4. **Scoring** — resolved in `didBegin(_:)`: `holeCat` → 3 pts + `sinkIntoHole()`; `webCat` → 0 pts + `stickToWeb()`; `boardCat`/`groundCat` → `scheduleSettleCheck()` waits 0.45 s for the bag to come to rest (velocity < 80) before awarding 1 pt (board) or 0 pts (ground miss). `stoneCat`/`wallCat` just spark + haptic and let physics continue.

**Physics layout** (built once in `buildShaft`/`buildBoardAndGround`/`buildBag`):

| Category bit | Where | Role |
|--------------|-------|------|
| `bagCat` (1<<0) | `bag.physicsBody` | Dynamic circle (`radius = bagSize*0.7`); high linear/angular damping; `usesPreciseCollisionDetection`. Built `isDynamic = false` (and `alpha = 0`, along with its shadow) so it stays frozen and hidden during tutorial + countdown |
| `wallCat` (1<<1) | Two static side walls running the shaft length | Bag bounces off the brick (`restitution 0.35`) |
| `stoneCat` (1<<2) | Static stones placed by `buildObstacles()` **and** player-tapped rocks | Bouncy (`restitution 0.55`) — knocks the bag sideways |
| `webCat` (1<<3) | Static sensor on spider-web obstacles | Catches the bag and ends the turn (0 pts) |
| `boardCat` (1<<4) | Two static chunks flanking the hole inside the board node | Bag lands on the wood → 1 pt after settle |
| `holeCat` (1<<5) | Static sensor in the gap between the chunks (`collisionBitMask = 0`) | Bag falls through → 3 pts |
| `groundCat` (1<<6) | Solid static dirt strip below the board | Catches off-board misses → 0 pt; bag cannot pass through |

Bag `collisionBitMask = wallCat | stoneCat | boardCat | groundCat` (it physically rests on these); `contactTestBitMask` additionally includes `webCat | holeCat` (sensors).

**Board / hole** — the wood board is drawn procedurally by `makeBoardTexture(...)` (no PNG asset). The hole sits at `holeLocalX` on the left; a pulsing additive **yellow guide beam** (`makeBeamTexture`) rises from the hole up the shaft so the player can aim toward it. Walls use `makeBrickTexture`, stones `makeStoneTexture`.

**Entry points:**
- `MiniGamePickerScene` → `"wellflinger"` card (`onComplete = { _ in }`).
- No world trigger yet.

**Tutorial key** — `TutorialManager.wellFlinger` (`"tutorial.wellFlinger.v1"`).

**Start flow (tutorial → countdown)** — the bag's physics body is built with `isDynamic = false` and the bag + shadow start at `alpha = 0`, so the bag stays frozen and invisible at the top of the well during the tutorial. `presentTutorial` sets `tutorialUp = true` and, if a turn is live (e.g. the `?` help button is opened mid-fall), saves the bag's velocity and freezes it; while `tutorialUp` the `update()` loop early-returns so the camera doesn't pan and stuck-detection doesn't run. On tutorial completion `tutorialUp` clears and either `startCountdown()` runs (first-play / `autoTriggered`) or the saved velocity is restored to resume a paused live turn.

After the tutorial (or immediately, if already seen), `startCountdown()` runs the same `3 / 2 / 1 / GO` beat sequence as `BeachBallCornholeScene` — labels are added to `camNode` (which tracks the bag) so they stay screen-centered. The final `GO` beat clears `countdownActive` and calls `startTurn()`, which makes the bag dynamic, reveals it (`alpha = 1`), and releases the drop. While `countdownActive` is true, rock placement in `touchesBegan` is blocked and the `update()` stuck-detection (`"BAG STUCK!"`) is suppressed. Replay-after-loss (`resetForReplay()`) calls `startTurn()` directly — no countdown.

> **TutorialOverlay completion** — `TutorialOverlay.finish()` fires its `onComplete` callback *before* `removeFromParent()` in the action sequence. Removing the node first can drop later actions in the same sequence (the node leaves the scene tree), which previously skipped the post-tutorial start path. This applies to every mini-game that starts on the tutorial callback.

**Asset note** — the board, walls, stones, and guide beam are all generated procedurally (no `cornholeBoard_side.png` or other board asset needed). The bag uses `bag_16bit` from `Assets.xcassets`.

### Story System

`StoryModuleScene` displays story chapter text over a full-screen panel. Body text `fontSize` is capped at `min(14, W / 17)` — keep this value at 14 to match the pixel-art scale.

#### Data model (`StoryData.swift`)

| Type | Purpose |
|------|---------|
| `StoryModule` | One story beat: `id`, `title`, `imageColor`, `text`, `choices[]`, `autoOutcome` |
| `StoryChoice` | A button label + `StoryOutcome` |
| `StoryOutcome` | `.nextModule(id:)` / `.spawnOnMap(StorySpawnConfig)` / `.miniGame(type, winID, loseID)` / `.returnToMenu` |
| `StoryMiniGame` | `.cornholeVs(opponent:)` / `.baseballVs(difficulty:)` / `.beehive` / `.bike` |
| `StorySpawnConfig` | Bundles `x?`, `y?`, `trigger?`, `nextModuleID?`, `flags[]` for a world spawn |
| `StoryFlag` | `dogsEnabled` / `baseballEnabled` / `batFound` / `questAccepted` |
| `BaseballAIDifficulty` | `standard` / `powerHitter` (Jen) / `greatFielder` (Tom) |

`StoryManager.shared` persists three things to `UserDefaults`:
- `currentModuleID` — which module to show next (key `storyCurrentModuleID_v1`)
- `pendingWorldTrigger` — string GameScene checks on A-press (key `storyWorldTrigger_v1`)
- flags array — set of enabled `StoryFlag` raw values (key `storyFlags_v1`)

`StoryManager.reset()` clears all three keys.

#### World-trigger strings (defined as `StoryManager` static constants)

| Constant | Value | Fires when player A-presses near |
|----------|-------|----------------------------------|
| `triggerCornhole` | `"cornhole_story"` | Any cornhole board tile |
| `triggerBat` | `"bat_story"` | Story bat pickup object |
| `triggerBaseball` | `"baseball_story"` | Baseball tile |
| `triggerBridge` | `"bridge_story"` | Bridge wood tile |
| `triggerQuestOffer` | `"quest_offer"` | Baseball tile (quest re-offer) |

When a trigger fires, `GameScene` clears `pendingWorldTrigger` and calls `launchStoryAtCurrentModule()`, which transitions to `StoryModuleScene.startAtCurrentProgress()`.

#### `StorySpawnConfig` pattern

`spawnOnMap` outcomes set `nextModuleID` on `StoryManager.currentModuleID` and `trigger` on `pendingWorldTrigger` **before** presenting `GameScene`. This means re-entering the world and pressing A near the right object will always resume the story at the correct module, even after a cold relaunch.

#### Bike race routing

`StoryModuleScene` presents `BikeDodgeViewController` modally (not as an SK scene swap). `BikeDodgeViewController.onDismissWithResult: ((Bool) -> Void)?` delivers the win/loss after the VC dismisses, captured from `BikeDodgeScene.onComplete`. `StoryModuleScene.launchMiniGame(.bike)` sets this callback to call `transitionToModule(id:)` directly — no `queuedModuleID` / `didMove` round-trip needed.

#### Baseball AI difficulty

`CornholeBaseballScene.aiDifficulty: BaseballAIDifficulty` (default `.standard`):
- `.powerHitter` — AI hits 35% harder (`aiPowerBoost = 1.35`) and 45% wider (`vxSpread * 0.45`); used for Jen
- `.greatFielder` — AI fielder error ±14 pt (vs standard ±38) and 10-frame reaction delay (vs 20); used for Tom

#### Bee difficulty ramp

`BeeHiveScene` tracks a global fight count in `UserDefaults` key `beeHiveFightCount_v1`. On each launch the speed multiplier is `min(1.0 + count * 0.12, 2.2)`. `dismissScene(playerWon:)` increments the count regardless of outcome.

#### Story bat pickup

During the bat-search phase (`pendingWorldTrigger == "bat_story"`), `GameScene.spawnStoryBatIfNeeded()` places a floating bat `SKNode` at `StoryManager.batWorldPosition` (currently `CGPoint(x: 380, y: 260)` — **tune this to match the actual map**). Pressing A near it calls `collectStoryBat()` → clears the node → launches `launchStoryAtCurrentModule()` with module `p1_bat_found`.

#### Part 1 module chain

```
p1_birthday → p1_last_day → [bike]
  win → p1_race_win → [world: cornhole trigger]
  lose → p1_race_retry (RETRY / GIVE UP)

[cornhole board A-press]
p1_jen_intro → [cornhole vs .jenny]
  win → p1_jen_win → [cornhole vs .tom]
    win → p1_tom_win → [world: bat trigger, sets dogsEnabled]
    lose → p1_tom_lose (REMATCH / QUIT)
  lose → p1_jen_lose (REMATCH / QUIT)

[bat A-press]
p1_bat_found → [world: baseball trigger, sets batFound + baseballEnabled]

[baseball tile A-press]
p1_baseball_jen_intro → [baseball vs .powerHitter]
  win → p1_baseball_jen_win → [baseball vs .greatFielder]
    win → p1_baseball_tom_win → choice: ACCEPT / FORGET IT
      ACCEPT → p1_quest_accept → [world: bridge trigger, sets questAccepted]
      FORGET → [world: quest_offer trigger]
    lose → p1_baseball_tom_lose (REMATCH / QUIT)
  lose → p1_baseball_jen_lose (REMATCH / QUIT)

[bridge A-press]
p1_bridge_intro → [world: stays at p1_bridge_intro — end of Part 1]
```

#### Dog gating

`GameScene.spawnDog()` is guarded by `StoryManager.shared.hasFlag(.dogsEnabled)`. Dogs are disabled until the `p1_tom_win` module fires (which sets the flag via `StorySpawnConfig.flags`). In free-play (no story progress), dogs never appear unless the flag is set.

### HUD Design System (Bit-Wood Brawler)

Every mini-game, picker, and stats scene uses a standardized top ribbon. When building or modifying any HUD, follow these rules exactly.

#### Color constants

| Role | Hex | Usage |
|------|-----|-------|
| Primary (dark wood) | `#1a0a04` | Ribbon background |
| Gold | `#f0c060` | Bottom border, active labels, titles |
| Heart red | `#d4441e` | Heart sprites, health indicators |
| Timer blue | `#5a9cd4` | Countdown timers, time labels |
| Iron gray | `#595959` | Inactive elements, bolt corners |

#### Top ribbon layout

Every scene has a 48pt ribbon that extends through the Dynamic Island / notch using the safe-area inset:

```swift
let topInset  = view?.safeAreaInsets.top ?? 0
let topH: CGFloat = 48
let totalTopH = topH + topInset

// Bar background extends through the notch
let bar = SKSpriteNode(color: dsPrimary, size: CGSize(width: W, height: totalTopH))
bar.position = CGPoint(x: 0, y: H / 2 - totalTopH / 2)

// 2px gold bottom border
let border = SKSpriteNode(color: dsGold, size: CGSize(width: W, height: 2))
border.position = CGPoint(x: 0, y: H / 2 - totalTopH + 1)

// Content centered in the visible 48pt band (below the notch)
let contentY = H / 2 - topInset - topH / 2
```

#### Three-zone structure

- **Zone A (left, x = −W/2 + 22):** `pauseIcon` PNG sprite, 22×22 pt, named `"pauseBtn"`
- **Zone B (center):** game state — hearts, scores, timers, or title label
- **Zone C (right, x = W/2 − 22):** `closeIcon` PNG sprite, 22×22 pt, named `"closeButton"` (or `"back"` on non-game scenes)

Always use the bundled `pauseIcon.png` and `closeIcon.png` assets. Never draw pause/close UI from scratch.

#### Touch routing

Use `nodes(at: loc)` — never `atPoint(loc)` — so the CRT overlay (highest zPosition) does not shadow named nodes:

```swift
// Correct
if nodes(at: loc).contains(where: { $0.name == "pauseBtn" }) { pauseGame(); return }

// Wrong — atPoint returns the topmost node (CRT overlay) which has no name
let name = atPoint(loc).name  // ← never do this for HUD routing
```

#### CRT overlay

Every scene adds a full-screen CRT scanline sprite via `addCrtOverlay()` at `zPosition = 100` (or higher). It must sit above all game content but have `isUserInteractionEnabled = false`.

**`CornholeBaseballScene` special case** — because a `UIHostingController` (SwiftUI HUD) is added as a UIKit subview on top of the `SKView`, the SK CRT sprite is invisible over the HUD area. A matching UIKit `UIView` CRT overlay is added as the topmost subview in `injectHUD(into:)` and removed in `willMove(from:)`. See `makeCRTView(frame:)` in `CornholeBaseballScene.swift`.

#### Baseball scene (SwiftUI HUD)

`CornholeBaseballScene` is the only scene with a SwiftUI overlay (`BaseballHUDView` via `UIHostingController`). Because all UIKit subviews render above the SK layer:

- The SwiftUI view covers the entire screen but only has opaque content in the top ribbon area; the rest is transparent so SK game content shows through.
- Pause and close buttons are `UIButton` instances (not SK sprites) added to the `SKView` above the hosting controller. They are sized to 44×48 pt tap targets with the icon image explicitly resized to 22×22 pt via `resizedIcon(named:to:)`.
- A UIKit CRT `UIView` is added last (`bringSubviewToFront`) so it sits above the buttons and SwiftUI view.
- `pushHUD()` updates the `BaseballHUDViewModel` on the main queue; the SwiftUI view observes and redraws automatically.
- All UIKit subviews (hosting controller, pause button, close button, CRT view) are stored as `private var` optionals and removed in `willMove(from:)`.

#### World action buttons

The bottom-right control area has four action buttons, stacked right-to-left at 26pt radius, 14pt gap each:

| Button | Name | Color | Visibility | Action |
|--------|------|-------|------------|--------|
| A | `"btn_a"` | Crimson | Always | Interact / climb |
| B | `"btn_b"` | Bronze | When player has bags | Throw beanbag |
| Biscuit | `"btn_biscuit"` | Dark wood + gold border | When `dogBiscuit` count > 0 | Place dog biscuit |
| Lance | `"btn_lance"` | Dark wood + gold border | After winning Suburban Jousters (`"goldenLanceEarned_v1"`) | Interact with high objects (TBD) |

`btnLance` is created in `setupActionButtons()` by `makeLanceButtonContent()` and its visibility is initialized from `UserDefaults` on every scene load so it persists across launches.

#### Adding a HUD to a new mini-game

1. Follow the safe-area ribbon pattern above in `setupHUD()` or equivalent.
2. Add `pauseIcon` (Zone A) and `closeIcon` (Zone C) at 22×22 pt.
3. Add a `TutorialHelpButton.make()` just right of the pause icon (x = −W/2 + 52).
4. Call `addCrtOverlay()` last so scanlines sit on top of all game content.
5. In `touchesBegan`, use `nodes(at:)` and check for `"pauseBtn"` before any other game input.

### Asset Notes

- All PNGs and the `.tmx` file must be added to **Copy Bundle Resources** in Xcode. Xcode's "synchronized folders" setting does not copy `.tsx` files, so tilesets are resolved purely from PNGs at runtime.
- `filteringMode = .nearest` is set on every texture and on `SKView.layer.magnificationFilter` to preserve pixel-art crispness.
- The font `PressStart2P-Regular` is used throughout the UI (menus, HUD, stats screen, story module) — it must be included in the bundle and declared in `Info.plist` under `UIAppFonts`.
