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
3. Composites **all tileset PNGs into one shared atlas texture** (shelf-packed with a 2 px gutter, built at load time in `packTilesets`); every tile sprite samples a sub-rect of that single texture so SpriteKit batches tiles across tilesets into the same draw call.
4. Builds `SKSpriteNode` tiles for each layer, returned as a `TMXMap` struct containing:
   - `layerGIDs` — raw GID grid per layer name
   - `layerNodes` — rendered `SKNode` per layer
   - `tilesetRanges: [(name: String, gidRange: ClosedRange<Int>)]` — every loaded tileset's lowercased basename and its assigned GID range

**Chunked rendering & culling** — within each layer, tile sprites are grouped under `TMXTileChunk` nodes covering `TMXMap.chunkCells` (10) × 10-cell blocks. Chunks sit at the layer origin and tiles keep absolute layer-space positions, so position-based lookups just need one extra nesting level (`layerNode.children` → chunks → tile sprites). `GameScene.updateChunkCulling()` (called from `updateCamera()`, re-runs only after ~4 tiles of camera travel) hides chunks outside the view + one-chunk margin via `TMXMap.cullChunks(outside:)` — off-screen tiles cost no render traversal. Sprite-level `isHidden` flags (opened chests, cleared trees) are independent of chunk hiding. The unit test `worldMapTilesResolveFromSharedAtlas` loads `World1` and validates the chunk hierarchy + atlas sub-rect math.

**Merged collision bodies** — `buildPhysics(from:)` merges consecutive blocked cells in a row into one wide static body. Runs never mix kinds: gate cells, grave cells, and normal solids merge only with their own kind (gate/grave runs still land in `gatePhysicsNodes`/`gravePhysicsNodes` and are removed as whole groups on unlock), and any blocker under an `ImaginationFX` tile stays **one body per cell** because `cacheBridgePhysicsNodes()` matches bridge blockers by exact tile-center position.

`GameScene` uses `tilesetRanges` to detect special tiles **by tileset name** (case-insensitive `contains`), not by hardcoded GID ranges. This means adding a new tileset in Tiled never requires touching code as long as the name contains the expected keyword. Detection mapping:

| Tileset name contains | Triggers |
|-----------------------|----------|
| `cornhole`            | Classic cornhole mini-game (board tiles are 2×2 groups) |
| `baseball`            | Beanbag baseball mini-game |
| `tree` (but not `apple`) | Tree climbing (safe zone) |
| `apple`               | Apple tree → cornhole vs. the Fairy Queen |
| `bee`                 | Beehive battle mini-game |
| `pool`                | Beach-ball cornhole |
| `bridge_stone`        | Beach-ball cornhole (same mini-game, different trigger) |
| `cave`                | Cornhole vs. Herman (long-distance board, dark cavern, dragon) |
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

### High Areas & the Golden Lance

Map layers whose name contains `"mountain"` are **always impassable** — `buildPhysics(from:)` walls every mountain cell and `isWalkable` rejects them, lance or no lance. The player can never stand on a high area.

What the Golden Lance grants instead is **knocking things off high areas**:

- `extractChestPositions(from:)` classifies each chest tile via `isOnHighArea(row:col:in:)` (cell inside a mountain region, or ≥ 4 of its 8 neighbors are mountain cells — covers chests painted on the mountains layer itself or on another layer over the plateau). High chests go to `highChestPositions`, ground chests to `chestPositions`.
- The axe pickup (chest art on the `"ax"` layer) is excluded from chest detection; when it sits on a high area, `extractAxPositions` adds it to the knockable list and records it in `highAxKeys` so it keeps its identity.
- With the lance, walking within 34 units of a high knockable shows the `▲A` prompt (no lance or nothing up there → no prompt). A-press runs `knockChestOffHighArea()`: the player faces the ledge (`PlayerNode.face(toward:)`), plays the sprite-sheet `attack` animation plus a gold lance-jab flourish (`playLanceJab(toward:)`), then the chest arcs off the ledge (`launchChestArc(from:to:)` — quad-curve flight, spin, squash-and-settle, `hit.mp3` + medium haptic).
- Landing spot (`chestLandingSpot(from:)`) walks from the ledge toward the player until `isWalkable`. The grounded sprite is tracked in `fallenChestNodes` (keyed `"<intX>,<intY>"` of the landing) and registered as a normal `chestPositions` entry (50/50 heart / dog biscuit via `openChest()`) — or as an `axPositions` entry if it was the axe. Both `openChest()` and `collectAxe()` remove the fallen sprite.
- Knock-downs **persist across launches** via `UserDefaults` key `"knockedHighKeys_v1"` (the set of `"<intX>,<intY>"` ledge positions that have been knocked off). `knockChestOffHighArea()` inserts the ledge key; on next load, `extractChestPositions`, `extractAxPositions`, and `extractTorchPositions` all check this set and call `hideChestTile(at:)` + skip detection for any matching tile. The fallen ground sprite itself is **not** persisted — if you knock something off and quit before collecting it, it's lost (same lossy contract for chests, axe, and torches). Opened-chest tracking (`openedChestKeys`) remains session-only since the knock-down persistence covers the cross-launch case.

### Bridge Wood

Tilesets whose name contains `"bridge_wood"` (e.g. `Bridge_Wood.tsx`) trigger `BridgePiranhaScene` when the player presses A nearby (36-unit radius). The prompt is suppressed once the bridge is unlocked.

On win, `unlockBridge()` runs:
1. Sets `UserDefaults` key `"bridgeUnlocked_v1"` to `true` — persists across launches.
2. Shows the `ImaginationFX` map layer (hidden by default; contains the visual bridge tiles over the river).
3. Removes the cached water-collision physics bodies (`bridgePhysicsNodes`) that sit under those tiles, making the river crossable.

On scene load, GameScene checks the flag and calls `unlockBridge()` immediately after `cacheBridgePhysicsNodes(from:)` so already-unlocked sessions see the bridge from the start.

### Mini-Game Pattern

Every mini-game follows the same contract:
```swift
var previousScene: SKScene?
var onComplete: ((Bool) -> Void)?
var awardsRewards: Bool   // default false
```
`GameScene` sets these before presenting the mini-game. The mini-game calls `onComplete?(won)` when finished, and `GameScene`'s closure re-presents itself. `hasSetup` in `GameScene` prevents double-initialization when the scene is re-presented after a mini-game returns.

`awardsRewards` gates **all** prizes — see **Result Modal & Reward Context** below.

`CornholeBaseballScene` additionally injects a SwiftUI `BaseballHUDView` as a `UIHostingController` onto the host `SKView` in `didMove(to:)` and removes it in `willMove(from:)`. It also supports a free-play **Jen/Tommy opponent picker** gated by `showOpponentPicker` — see **Story System → Baseball AI difficulty**.

`CornholeMiniGameScene` calls `CornholeStatsManager.shared.recordCornhole()` each time any bag enters the hole, and `recordWin()`/`recordLoss()` in `dismissScene(playerWon:)` before calling `onComplete`. This covers both in-world cornhole boards and the mini-games picker path.

### Result Modal & Reward Context

**One shared victory/defeat modal — `GameResultModal.swift`.** Every mini-game's end screen is built by `GameResultModal.make(sceneSize:won:title:subtitle:detail:hint:rewards:buttons:)`, which returns a fully-styled, pre-positioned `SKNode` (Bit-Wood Brawler look: dark-wood panel, gold-over-iron double border, `PressStart2P`, green title on win / red on loss, pulsing gold reward lines). Do **not** hand-roll a new game-over panel — extend this instead.

- Each scene supplies its **own** `Button`s, whose `name`s match the names its existing `touchesBegan` already dispatches on (`playAgainBtn`/`exitBtn`, `again`/`quitGame`, `continueBtn`, `replayBtn`/`menuBtn`, …). The modal sets that name on the button container **and** every child (body, border, label) so `nodes(at:)` routing matches a tap anywhere on the button. Swapping a scene's bespoke panel for the modal changes visuals only, never the flow.
- `Reward(item:count:text:)` renders a `+N ITEM` line with a colored item swatch; `Reward.unlock("…")` renders a plain gold line (e.g. `"BASEBALL UNLOCKED"`). The panel grows taller to fit reward rows + extra buttons.

**`awardsRewards` is the single switch for "is this story/world play or menu play?"** Each scene defaults it to `false`. The contract:

| Host | Sets `awardsRewards` | Grants items? |
|------|----------------------|---------------|
| `GameScene` (world-map triggers) | `true` | yes |
| `StoryModuleScene` (narrative fights) + `BikeDodgeViewController` | `true` | yes |
| `MiniGamePickerScene` (the menu) | leaves `false` | **never** |

When `false`, scenes pass an empty `rewards:` array (no prize lines) and skip setting their `*Earned` properties, so the picker path can never grant a prize. Never re-introduce an item grant inside the picker — it violates this rule (two such leaks, a test fire-bag grant and a Jousters lance grant, were removed).

**Reward table** (granted only when `awardsRewards == true`):

| Mini-game / outcome | Reward |
|---------------------|--------|
| BeanBag Bike — 1st place | Unlocks the world map (`ProgressManager.worldUnlocked`); plus any golden bags earned mid-race |
| Cornhole vs `.bully` | 10 coins (`coinsEarned`) |
| Cornhole vs `.billy` (Billy Badger) | 10 coins **+** 3 bomb bags (`coinsEarned` + `bombBagsEarned`) — stacked |
| Cornhole vs `.spirit` (Fairy Queen) | 6 magic bags (`magicBagsEarned`) |
| Cornhole vs `.ricky` (Ricky) | No item — story-only unlock line ("YOU'RE INVITED TO THE PARTY!") |
| Cornhole — beat both Tim **and** Jenny | Earns a baseball → baseball mini-game unlocked (`CornholeStatsManager.baseballUnlocked`) |
| BeeHive win | 3 honey bags |
| BeachBall win | 8 `floatingBag`s |
| Piranha Bridge win | Earns the bridge (`unlockBridge()` — cross the river) |
| Baseball — beat both Jen **and** Tim | Earns a bat → Suburban Jousters unlocked (`joustersUnlocked`) |
| Suburban Jousters — first win | Golden Lance (`"goldenLanceEarned_v1"`) |
| Well Flinger win | 3 fire bags (`fireBagsEarned`) |
| Cornhole vs `.barnum` (Herman) | 3 fire bags (`fireBagsEarned`) |

Scenes expose their winnings as `private(set) var …Earned` properties; the host's `onComplete` reads them after the closure fires and calls `inventory.collect(...)`. Consumable bags carried *into* a game (`available…Bags`) are deducted via `…BagsUsed` the same way.

**`ProgressManager.swift`** — singleton owning cross-session progression flags that had no home, chiefly `worldUnlocked` (persisted `UserDefaults` key `"worldUnlocked_v1"`, set on the first BeanBag Bike win). It also exposes convenience accessors (`hasBaseball`, `hasBat`, `hasBridge`, `hasLance`) that mirror the existing stat/`UserDefaults` unlocks so gate checks read uniformly. **World-map gating note:** the world (`GameScene`) is reachable only through the story, which already sequences the bike race before the world, so the unlock is enforced by that ordering; the flag exists for any future direct free-roam entry point.

### Cornhole Opponents

`CornholeMiniGameScene` supports opponents selected via `OpponentPickerNode` before the game starts. The host scene can bypass the picker by setting `mini.preSelectedOpponent = .spirit` (etc.) before presenting — used by the apple tree world trigger (Fairy Queen) and the `cave` world trigger (Herman) to drop the player straight into a match. `.ricky` is reachable **only** via `preSelectedOpponent` from the story's party beat — there is no picker card for him.

Enum case names (`.tom`, `.barnum`, `.spirit`, …) predate the story's character renames and are kept as-is to avoid churn to save-data keys and internal call sites; only the **display names** shown to the player use the new names below.

| Opponent | Enum | Display name | Win score | Special rules |
|----------|------|---------------|-----------|---------------|
| Tim | `.tom` | TIM | 11 | Baseline AI, moderate accuracy. Random per-round chance to trigger "Tim's Fart" (green fog + faster indicator) |
| Jenny | `.jenny` | JENNY | 11 | Slightly tighter aim than Tim |
| Herman | `.barnum` | HERMAN | 11 | Long-distance board (`distanceScale 0.5`); dark cave scenery (no weather, no gophers); a dragon rises from the chasm and ignites airborne bags. Fixed "good-not-great" aim (`barnumNoiseFactor`). First board burn triggers a one-time "Sir Michael swaps the board" flavor beat (`showSirMichaelSwap()`) |
| Billy Badger | `.billy` | BILLY | 21 | Forced thunderstorm every round; adaptive difficulty; can throw bomb bags (~25% chance) |
| Fairy Queen | `.spirit` | QUEEN | 21 | Drops magic bags vertically from above (50% cornhole / 50% random board position) |
| Ricky Rogers | `.ricky` | RICKY | 21 | Tightest aim in the game (`rickyNoiseFactor = 1.3`). Story-only — once per match, at a tied score near the win line, he "tweaks his ankle" and airballs the throw entirely (`showRickySprainAnnouncement()`). During this match only, a narrative Jenny-vs-Becky side score ticker (`addSideScoreLabel()`/`advanceSideScore()`) advances each round below the top ribbon |

**Billy adaptive difficulty** — `billyNoiseFactor` starts from career cornhole accuracy (`cornholes / (totalGames × 12)`, clamped to `[1.4, 3.8]`). Each round the player wins tightens Billy by `−0.12`; each round Billy wins eases him by `+0.15`. Range stays within `[1.4, 3.8]`.

**Herman's cave match** (`applyHermanSettings()`) — win score 11, `distanceScale = 0.5` (same long board Billy uses), no rain/storm. `isCaveMatch = true` swaps the grass field for `applyCaveScenery()`: near-black cave floor, a bottomless chasm between the throw line and board's front edge, jagged rock lips, and stalactites. The chasm's world-Y band is stored in `caveChasmTopY`/`caveChasmBottomY`. **Chasm fall** — in a cave match, an off-board bag whose landing `by` falls inside that band is routed to `fallIntoChasm(_:)` instead of resting: it recedes into the depths — shrinking toward nothing in place (spin + fade, no downward screen translation, since the view is top-down), counts as a miss (0 pts), and is pulled out of collisions/scoring via `hasAppliedGroundScale` + the new `isFallingInChasm` flag. `maybeStartGopher` early-returns in cave matches, and `startRound()` calls `scheduleDragon()` instead of `scheduleCrow()`. **Dragon** — `scheduleDragon()` reschedules itself every 4–8 s (multiple strikes per round). `spawnDragon()` rises a programmatically-drawn dragon head (`makeDragonNode`) from the chasm at the bag-flight corridor height (`crowY`), then `breatheFlame(fromX:y:towardRight:)` lays a wide, organic, **sustained** flame across the lane (~2.2 s hold; built from layered, out-of-phase flickering lobes via `makeFlameLobe`, with rolling embers from `spawnFlameEmbers`). The dragon holds its pose for the whole burn. Ignition is **continuous** for the flame's duration (a repeating `"dragonFlameScan"` action), so any airborne bag (`!isGrounded`, `bz > 2`, not already on fire) that crosses an 80-pt vertical band at any point — **either player's** — is passed to `igniteBag(_:)`, which sets `isFire = true`, recolors it, adds a `🔥` flicker marker, and shows a fire poof. The ignited bag then triggers the normal `fireBag` board/hole burn behavior on landing. The dragon is torn down on round reset and game over (`dragonSchedule` action + `dragonNode`). No art asset — Herman's portrait is also drawn from scratch by the static `makeHermanPortraitTexture()` (ex-jock school janitor: thinning gray hair, gray mustache, old football jersey), used by both the picker card (via `OpponentConfig.textureOverride`) and the in-game portrait. The first board burn in a Herman match triggers a one-time "Sir Michael swaps the board" flavor beat (`showSirMichaelSwap()` — a small pixel boy darts across and a banner appears), cosmetic only.

**Fairy Queen drop mechanic** — `dropMagicBagFromAbove(targetX:targetY:)` places a `MiniGameBag(isMagic: true)` at `bz = 220` with zero `vx/vy`; existing bz-guard in `resolveBagCollisions()` prevents mid-air collisions. The magic bag falls straight down to its target.

**Bag destruction** — `destroyBag(_:)` sets `isDestroyed = true` and plays a scale/fade animation. Destroyed bags are skipped in `calculateRoundScore()` but stay in `activeBags` until round cleanup. `resolveBagCollisions()` skips destroyed bags.

**Rewards** — beating Billy awards 3 bomb bags **+ 10 coins**; beating the Fairy Queen awards 6 magic bags; beating Herman awards 3 fire bags; beating the generic `.bully` awards 10 coins; beating Ricky awards no item (pure story beat — a narrative "YOU'RE INVITED TO THE PARTY!" unlock line only). These are set on `bombBagsEarned` / `magicBagsEarned` / `fireBagsEarned` / `coinsEarned` in `dismissScene` (only when `awardsRewards`) and collected by the host's `onComplete`. See **Result Modal & Reward Context**.

### Opponent Picker Layout

`OpponentPickerNode` renders opponents in one of four layouts based on count:
- **2 opponents** — side-by-side cards
- **3 opponents** — 2 regular cards on top row, 1 boss card centered below
- **4 opponents** — 2×2 grid: top row regular (Tim, Jenny), bottom row boss (Billy, Fairy Queen) with red borders and `★ BOSS ★` badge
- **5 opponents** — 3 regular cards on the top row (Tim, Jenny, Herman), 2 boss cards on the bottom row (Billy, Fairy Queen). The first three configs are treated as regular, the last two as bosses. `OpponentConfig.textureOverride` lets a card use a pre-built texture (Herman's drawn portrait) instead of a named asset.
- The live picker also has a 6th card (CathyX) not reflected in this 5-tier layout description — see the actual layout logic in `OpponentPickerNode.swift` if extending further. Ricky has no picker card at all (story-only, via `preSelectedOpponent`).

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

- **`Item.swift`** — `ItemType` enum (`coin`, `bag`, `star`, `honeyBag`, `bombBag`, `magicBag`, `fireBag`, `goldenBag`, `dogBiscuit`, `floatingBag`, `goldenLance`) with `color`, `displayName`, and `hudSymbol`.
- **`InventoryManager.swift`** — holds `[ItemType: Int]` counts; fires an `onChanged` closure when any item is collected, plus an `onCollect(ItemType)` closure identifying what was collected. `GameScene` owns the instance.

**First-pickup use hints** — the first time a special item type is ever collected, `GameScene.maybeShowItemUseHint(for:)` shows a one-line use hint via `showHintBanner` (e.g. `"BOMB BAG: blows up / rival bags on board!"`). Copy lives in `itemUseHint(for:)`; seen types persist in `UserDefaults` under `"itemUseHintsSeen_v1"`. `inventory.onCollect` is registered **after** the boot-time lance-mirror and test grants in setup so those never fire hints. `floatingBag` and `goldenLance` are excluded — they already get bespoke award banners.

**Hint banner copy rule** — `showHintBanner` lines are separated by `\n`; keep each line ≤ 20 characters. PressStart2P glyphs are square (advance ≈ fontSize), so the 76%-width panel fits ~21 chars per line at full size; longer lines auto-shrink the font to fit rather than overflow. Concurrent hints queue (4.9 s spacing) instead of stacking.
- **`CollectibleNode.swift`** — `SKNode` subclass placed in the map's `mapNode`. Draws an 8×8 colored tile + glow ring, bobs gently, and pops/fades out on contact. Physics body is a sensor (`collisionBitMask = 0`, `contactTestBitMask = PlayerNode.categoryBit`). Uses `collectibleBit = 0x1 << 2`.
- **`InventoryHUDNode.swift`** — `SKNode` attached to `cameraNode`. Renders a horizontal row of dark pill slots (colored icon + `×N` count label) in the bottom chrome, vertically centered between the top of the D-pad cross and the stage bottom border. Call `refresh(counts:)` to redraw. Each slot container is named `"slot_<rawValue>"` (e.g. `"slot_dogBiscuit"`); `GameScene.handleTouchBegan` walks `nodes(at:)` for that prefix and routes the tap to `handleInventoryTap(_:)` for per-item world-use actions.

**Collection flow in `GameScene`:**
1. `setupPlayer()` ORs `CollectibleNode.collectibleBit` into the player's `contactTestBitMask`.
2. `spawnCollectibles(in:)` drops items around the player's spawn point after the map loads.
3. `didBegin(_:)` detects the contact, calls `item.collect()`, updates `InventoryManager`, and spawns a floating `+NAME` pickup label via `showPickupText(_:at:)`.

**Special bag items** (earned from boss opponents, usable in any cornhole game):
- **`honeyBag`** — immune to wind and bot knockback; sticks on board contact.
- **`bombBag`** — landing on the board destroys all opponent board bags; landing in the hole destroys all opponent hole bags. Billy can also throw bomb bags (~25% chance). Awarded (3) by beating Billy Badger.
- **`magicBag`** — physically intercepts opponent board bags on collision (opponent bag destroyed, magic bag keeps moving). Scoring in the hole destroys all opponent bags already scored in the hole this round. Awarded (3) by beating the Fairy Queen.
- **`fireBag`** — landing on the board burns all other board bags instantly (thrower keeps 1 pt, all others score 0); subsequent bags landing on the board that round are also destroyed. Sets `boardOnFire = true` until round reset. Landing in the hole burns all other cornholes scored that round by either player (thrower keeps 3 pts, all others score 0). Sets `holeFire = true`. Visuals: pulsing red-orange board overlay + rising ember particles + blinking "🔥 BOARD ON FIRE! 🔥" label. Awarded (3) by winning Well Flinger from the world map.
- **`cannonballBag`** — purchased from the store (20 coins each). Appears as a black sphere with a yellow glow. Cannot be stolen by the gopher (gopher spawn is suppressed). Passes through ducks/babies without stopping (the obstacle is knocked off screen but the bag maintains its trajectory). Immune to bag-vs-bag collisions and soft-bag deformation. When it lands on the board (not in the cornhole), it scores 3 pts immediately for the thrower and punches a new hole at the landing position. The new hole persists for the rest of the round — both player and opponent can score in it (3 pts, same as the main hole). Multiple cannonball holes can exist in one round. All cannonball holes and their visual nodes are cleared on round reset. If the cannonball enters the regular cornhole, it scores the normal 3 pts. State tracked via `cannonballHoles: [(center: CGPoint, radius: CGFloat)]` and `cannonballHoleNodes: [SKNode]`.

`GameScene` passes `availableBombBags` / `availableMagicBags` / `availableFireBags` / `availableCannonballBags` into `CornholeMiniGameScene` before presenting it, then deducts used counts and adds earned counts in the `onComplete` closure. `MiniGamePickerScene` reads the same `InventoryManager` (via a local instance) when launching cornhole directly from the picker.

**World-use items** (placed in the open world by tapping the inventory slot):
- **`dogBiscuit`** — earned from chests (50/50 with heart refill). Tapping the inventory slot calls `placeDogBiscuit()`, which decrements the count and spawns a bone-shaped `SKNode` at `player.position` (added to `map.mapNode`, tracked in `placedBiscuits: [PlacedBiscuit]`). In `updateDogs(dt:)`, any non-fleeing dog without a `biscuitTarget` checks for an unclaimed biscuit within an 80-unit sniff radius; first match wins and is claimed. The dog walks to the biscuit, eats for 3 seconds (`eatDuration` in `DogNode`), then `onFinishedEating` fires — the biscuit node pops/fades out and is removed from `placedBiscuits`. After eating, the dog resumes chasing the player.

**Cross-game bonus items:**
- **`floatingBag`** — awarded (8) by winning the BeachBall mini-game from the world map. Carried into `BridgePiranhaScene` via `availableFloatingBags`: they extend the bag pool beyond the base 12 (`bagsRemaining = baseBags + availableFloatingBags`). Only those thrown *beyond* the base 12 are consumed (`floatingBagsUsed`, deducted by `GameScene`'s `onComplete`). No cornhole or world-use action.

**Permanent unlock items** (not consumed; awarded once and persist via `UserDefaults`):
- **`goldenLance`** — awarded on first Suburban Jousters win (key `"goldenLanceEarned_v1"`). Reveals the `btnLance` action button in the world HUD. Used to interact with high objects in the world (TBD). The button is a dark gold-bordered circle drawn by `makeLanceButtonContent()` — a diagonal gold shaft, bright tip, and grip wrap.

**Fire bag round state** — reset at the start of each round in `startRound()`: `boardOnFire`, `holeFire`, `fireBoardOverlay`, `fireBoardEmitter` node (named `"fireBoardEmitter"`), and `fireBoardLabel` node (named `"fireBoardLabel"`).

**Losing to the Fairy Queen** — the game-over panel shows a green hint: *"SPECIAL BAGS MAY HELP AGAINST SUCH A FOE..."* to guide the player toward using magic/fire bags.

**To add more item types:** add a case to `ItemType`, give it a `color`/`displayName`/`hudSymbol`, and drop `CollectibleNode(type: .newType)` nodes in `spawnCollectibles(in:)`. If the item should be usable from the inventory HUD, add a case to `GameScene.handleInventoryTap(_:)` for its world-use action.

### Hearts System

`HeartsManager.shared` (singleton, `HeartsManager.swift`) owns a single universal heart count across the world map and every mini-game. Persisted to `UserDefaults` key `"universalHearts_v1"`; max is `5`.

- API: `currentHearts`, `lose()`, `gain()`, `set(_:)`, `refill()`, plus an `onChanged` closure for HUD sync while a modal mini-game (bike race) is up.
- **Hearts drain in:** BikeDodgeScene (crashes / bag hits), BeeHiveScene (bee stings — synced back to `HeartsManager` via `remainingHearts`), and GameScene (enemy bite). Score-based games (cornhole, baseball, beachball) don't drain the universal count.
- **Hearts refill on:** cold app launch (`LoadingScene.didMove`), world-map game over (`GameScene.triggerGameOver`), in-game pickups (`PickupData.heart` in bike race), and on **replay-after-loss** in any heart-draining game (`BikeDodgeScene.resetGame`, `BeeHiveScene.restartGame`). A 0-hearts guard on entry into the bike race and beehive (both from world and picker paths) also refills, so players can't enter a heart-draining game with 0 hearts.
- **Mini-game entry:** heart-draining scenes start with `HeartsManager.shared.currentHearts` (may be less than max if the player took damage earlier in the session). They do not reset to max on entry — only on replay-after-loss.
- `GameScene` registers `HeartsManager.shared.onChanged` in `didMove(to:)` so its HUD redraws when the bike-race modal updates the count off-screen, then calls `resyncHeartsDisplay()` on any return path.

### Pause Map

The world pause overlay (pause button → `showPauseOverlay()`) has two buttons: RESUME and MAP. MAP opens `showMapOverlay()` — a fog-of-war world map drawn over the pause panel; any tap closes it and returns to the pause panel.

- The map is a virtual grid of screen-sized cells (`stageWorldSize` per side) covering the TMX map. Cells the player has walked through are recorded by `trackVisitedCell()` (called from `update()`) into `visitedCells: Set<String>` (key = `"<col>,<row>"` from `cellKey(for:)`), persisted to `UserDefaults` under `"visitedMapCells_v1"`.
- Visited cells render wood-filled; unvisited cells stay dark.
- **Pins appear only in visited cells** (discovery log): gold squares for mini-game triggers (cornhole boards, baseball, apple trees, beehives, pools, both bridges, wells, fences) and a blue square for the store. Adjacent trigger tiles (2×2 boards, fence runs) are collapsed to one pin per 64-unit bucket by `clusteredPins(_:bucket:)`.
- A pulsing red dot marks the player's current position; a 3-item legend (YOU / GAMES / SHOP) sits in the panel footer.

### Tutorial System

Centralized framework that every mini-game uses for consistent first-play onboarding.

- **`TutorialManager.swift`** — singleton tracking which tutorials have been seen (`UserDefaults`). Static keys per game: `.bike`, `.cornhole`, `.baseball`, `.beehive`, `.beachball`, `.piranha`, `.jousters`, `.wellFlinger`, `.horseRace`, `.kickball`, `.mopChase`; `allKeys` lists them all. API: `hasSeen(_:)`, `markSeen(_:)`, `reset(_:)`, and `resetAll()` (clears every key — used by `SettingsScene`).
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
| `moveSpeed` | PlayerNode | 85.0 | Player world-units per second |
| `totalCycles` / `outsPerHalf` / `strikesPerOut` | CornholeBaseballScene | 3 / 3 / 3 | Baseball: 3 innings; each batting half ends at 3 outs; 3 strikes = 1 out |
| `eatDuration` | DogNode | 3.0 | Seconds a dog spends eating a placed biscuit |
| `collectibleBit` | CollectibleNode | `0x1 << 2` | Physics category for collectible items |
| `enemyBit` | PlayerNode | `0x1 << 3` | Physics category reserved for enemies |
| `batWorldPosition` | StoryManager | `CGPoint(x:380, y:260)` | World position of story bat pickup — tune to map |
| `storyBatRadius` | GameScene | 28 | Proximity radius for story bat A-press |

Hardcoded GID ranges for world-trigger tiles are gone — see the "tileset name contains" table in the **Map System** section above for the current detection contract.

### Suburban Jousters

`SuburbanJoustersScene` is a backyard bicycle jousting mini-game. The player rides the left lane; an AI rival descends the right lane. Dual-zone touch: left half pedals/slides shield, right half sweeps lance aim. Heart-draining: each crash costs a heart; first to drop the rival's 3 lives wins.

**World trigger** — any non-zero tile on the `"fences"` map layer (detected by layer name, not tileset name). Pressing A within 36 world units opens the scene via `openSuburbanJousters()`.

**Gate (free-roam only — the story reaches Jousters directly via `.miniGame(.jousters,...)`, ungated).** `CornholeStatsManager.shared.joustersUnlocked` (`defeatedJenBaseball && defeatedTomBaseball`) controls the free-roam fences-layer trigger:
- Neither beaten → hint: *"In order to joust on your bike, you need something to use as a lance."*
- Only Jen beaten → hint: *"Beat Tim at baseball to unlock the joust."*
- Both beaten → scene launches.

**Baseball sequencing (free-roam)** — `openCornholeBaseball()` in `GameScene` automatically sets the correct AI difficulty based on progress:
1. First visit: `aiDifficulty = .powerHitter` (Jen). Win sets `defeatedJenBaseball`.
2. Second visit: `aiDifficulty = .greatFielder` (Tim, legacy `defeatedTomBaseball` key name unchanged). Win sets `defeatedTomBaseball` and shows the *"The joust awaits!"* banner.
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
- World trigger — any tileset whose name contains `"well"` (`Well.tsx`/`well.png`). `extractWellPositions(from:)` collects tile centers into `wellPositions`; A-press within range calls `openWellFlinger()`, which sets `awardsRewards = true` and passes `availableBags`/`availableFireBags` from inventory. Win awards 3 fire bags (same reward table as the picker path).

**Tutorial key** — `TutorialManager.wellFlinger` (`"tutorial.wellFlinger.v1"`).

**Start flow (tutorial → countdown)** — the bag's physics body is built with `isDynamic = false` and the bag + shadow start at `alpha = 0`, so the bag stays frozen and invisible at the top of the well during the tutorial. `presentTutorial` sets `tutorialUp = true` and, if a turn is live (e.g. the `?` help button is opened mid-fall), saves the bag's velocity and freezes it; while `tutorialUp` the `update()` loop early-returns so the camera doesn't pan and stuck-detection doesn't run. On tutorial completion `tutorialUp` clears and either `startCountdown()` runs (first-play / `autoTriggered`) or the saved velocity is restored to resume a paused live turn.

After the tutorial (or immediately, if already seen), `startCountdown()` runs the same `3 / 2 / 1 / GO` beat sequence as `BeachBallCornholeScene` — labels are added to `camNode` (which tracks the bag) so they stay screen-centered. The final `GO` beat clears `countdownActive` and calls `startTurn()`, which makes the bag dynamic, reveals it (`alpha = 1`), and releases the drop. While `countdownActive` is true, rock placement in `touchesBegan` is blocked and the `update()` stuck-detection (`"BAG STUCK!"`) is suppressed. Replay-after-loss (`resetForReplay()`) calls `startTurn()` directly — no countdown.

> **TutorialOverlay completion** — `TutorialOverlay.finish()` fires its `onComplete` callback *before* `removeFromParent()` in the action sequence. Removing the node first can drop later actions in the same sequence (the node leaves the scene tree), which previously skipped the post-tutorial start path. This applies to every mini-game that starts on the tutorial callback.

**Asset note** — the board, walls, stones, and guide beam are all generated procedurally (no `cornholeBoard_side.png` or other board asset needed). The bag uses `bag_16bit` from `Assets.xcassets`.

### Horse Race (Cornhole Derby)

`HorseRaceCornholeScene` is a simultaneous-throw cornhole derby. One wooden board with **three holes** along its central axis: large/closest = **+1 space**, medium = **+2**, small/farthest = **+3** (each labeled `+N` in gold on the board). Two pixel horses race left-to-right above the board on a wooden lane with 13 tick marks; first horse to reach **12 spaces** wins.

**Picker-only mini-game.** `awardsRewards` stays `false` and the scene passes an empty `rewards:` array — no item is granted, per the "menu play never grants a prize" rule. Currently only reachable from `MiniGamePickerScene` (no world trigger).

**Flick mechanic** — identical to `CornholeMiniGameScene`. A red bag (`turnIndicator`) oscillates left-to-right along `throwLineY` at `targetSpeed = W * 0.65` within `±boardHalfW * 1.30`. Swipe direction = arc; swipe length = power. Bag launches from `turnIndicator.position.x` (not the touch start), so the player aims via timing and powers via swipe length. 14pt minimum swipe length to filter out accidental dud bags. `powerScale` is calibrated so an `H * 0.34` swipe lands near the **medium** hole.

**Simultaneous play** — no turns. Each side has its own cooldown: a new bag may be thrown as soon as the side's previous bag is `isGrounded || hasScored`. The indicator hides during the player's cooldown and reappears the moment the previous bag touches down.

**AI scheduling** — `aiReadyTime` is a `TimeInterval` (scene time). After each AI throw, `aiReadyTime = currentSceneTime + random(0.55…1.05)`. The AI is allowed to throw when its previous bag has touched down **and** `currentSceneTime >= aiReadyTime` — produces a human-feeling pace without spamming.

**Bag-vs-bag collisions** — elastic, copied from `CornholeMiniGameScene.resolveBagCollisions` (`restitution = 0.68`, bag radius 22). Scored bags and off-board grounded bags are excluded so a bag in the hole stays sunk and a bag that fell off doesn't shove later landings around.

**Opponent picker** (`presentOpponentPicker()`) — runs **before** the tutorial/countdown. Two Bit-Wood cards named `"horseOpp_tommy"` and `"horseOpp_jen"`; `touchesBegan` walks the parent chain to route the tap to `selectOpponent(_:)`. `awaitingOpponentChoice` blocks input, the `update()` loop, and AI throws until a choice is made. Replay-after-loss keeps the same opponent (no re-pick).

**Opponent profiles** — drive hole preference and aim noise (lower noise multiplier = tighter aim):

| Opponent | P(large +1) | P(med +2) | P(small +3) | accLarge | accMed | accSmall |
|----------|-------------|-----------|-------------|----------|--------|----------|
| `.tommy` | 0.70 | 0.20 | 0.10 | **0.95×** | 1.55× | 1.85× |
| `.jen`   | 0.22 | 0.60 | 0.18 | 1.55× | **0.95×** | 1.70× |

Aim noise: `noise = hole.radius * accMul`; aimX uniform in `±noise`, aimY in `±noise * 0.6`. **Catch-up**: when `playerSpaces - aiSpaces >= 5`, a 40% per-throw roll forces a higher-tier shot (65% small / 35% medium) so the AI can claw back.

**Start flow** — `didMove`:
1. Layout / world / board / lane / UI / CRT (indicator hidden).
2. `presentOpponentPicker()`.
3. On selection → tutorial-or-countdown.
   - First play: `presentTutorial(autoTriggered: true)` (3 cards: goal, hole values, throw mechanic). On overlay completion: `TutorialManager.shared.markSeen(.horseRace)` then `startCountdown()`.
   - Repeat plays: `startCountdown()` directly.
4. `startCountdown()` runs the `3 / 2 / 1 / THROW!` beat sequence (same pulse/scale beats as `BeachBallCornholeScene`). The final beat clears `countdownActive`, unhides `turnIndicator`, and pushes `aiReadyTime` 0.3 s forward so the AI doesn't fire instantly.

While `awaitingOpponentChoice`, `tutorialUp`, or `countdownActive` are true, `touchesBegan`/`touchesEnded` reject throws and the `update()` loop early-returns (no oscillation, no AI throw, no bag physics).

**HUD help button** — standard `TutorialHelpButton.make()` at `(-W/2 + 52, contentY)` re-presents the tutorial without restarting the race (the saved-seen flag is not flipped; no game state is touched).

**Replay** — `resetForReplay()` clears bags, resets spaces and horse positions, hides the indicator, sets `aiReadyTime = 0`, and calls `startCountdown()` so each rematch starts on the same 3-2-1 beat. Opponent is preserved.

**HUD copy** — score label reads `RED \(playerSpaces)  |  \(opponentName) \(aiSpaces)` (e.g., `RED 4  |  TIM 7`). Game-over modal subtitle: `RED \(playerSpaces)  -  \(aiSpaces) \(opponentName)`.

**Tutorial key** — `TutorialManager.horseRace` (`"tutorial.horseRace.v1"`); included in `allKeys` so `SettingsScene` "reset tutorials" covers it.

**Entry points:**
- `MiniGamePickerScene` → `"horseRace"` card (`onComplete = { _ in }`).
- No world trigger.

### Kickball (Dream at the Plate)

`KickballScene` is the Chapter 2 dream sequence: kickball on the school pavement, bases loaded, first HIT in 3 tries wins. Center-origin scene, manual ball motion in `update()` (no SKPhysics).

**Per-pitch flow** (`TryPhase`: `idle → pitching → running → ballInFlight → resolving`):
1. **AIM** — while the ball rolls from the pitcher (top) to the plate (bottom, `pitchDuration = 2.3 s`, slight sine wobble), a horizontal swipe rotates the gold aim arrow at the plate (`aimAngle`, clamped ±0.30π).
2. **RUN** — a tap (< 12 pt movement) starts Jack's sprint to the plate, which takes exactly `runSpeedRampTime` (1.1 s) with the speed meter filling 0→1 across it. **Reaching the plate while the ball is still rolling = dead stop**: momentum and power drop straight to zero ("STOPPED AT THE PLATE!", meter turns red, Jack slumps). The run start is the core timing decision — arrive together with the ball.
3. **KICK** — the red KICK button (bottom-right, name `"kickBtn"`) appears when the run starts and pulses faster as the ball nears the plate (`pulseKickButtonIfRateChanged`). It fires on **touch-down** (checked in `touchesBegan` before the generic button walk) for timing feel.

**Kick resolution** (`resolveKick()`): timing quality falls off linearly over `whiffWindow` (64 pt from plate; beyond = "WHIFF!"). `power = 0.30 + 0.70 × (0.55·timing + 0.45·runSpeed)`; a stalled kicker (`runSpeedFactor < 0.05`) has power capped below `hitPowerThreshold`, so a standing kick can never be a hit ("NO LEGS — EASY OUT!"). Timing error skews the direction (early pulls, late pushes). Outcome decided at the moment of the kick, then animated:
- `|angle| > foulAngle (±43°)` → **FOUL** (failed try)
- `power < hitPowerThreshold (0.62)` → **FIELDED — OUT** (nearest defender chases the projected stall point)
- otherwise → **HIT**, with tiered flavor text ("PAST THE INFIELD!" / "DEEP INTO THE OUTFIELD!" / "OVER EVERYONE'S HEADS!")
- Never starting the run, or the ball rolling 1.25× past the plate → **STRIKE** / "TOO LATE!"

**Pause-clock note** — the pitch is driven by scene-time deltas, so `pauseGame()`/`resumeGame()` maintain `pauseTimeShift` to keep the ball from teleporting after a pause.

**Dream dressing** — `addDreamOverlay()` (drifting white haze blobs + pale radial vignette at `zPosition 750`, under the CRT at 800); chalk foul lines/bases on hot-pavement gray; sideline watchers include a curly-brown-haired Kim per the memoir. All characters are `makeKid(shirt:hair:)` two-block pixel kids — no art assets.

**Entry points:**
- Story: `p1_kickball` module → `.miniGame(.kickball, winID: "p1_kickball_dream", loseID: "p1_kickball_retry")`. The win reveals it was a concussion dream; `p1_kickball_vision` then narrates what actually happened.
- `MiniGamePickerScene` → `"kickball"` card (`onComplete = { _ in }`).

**No rewards in any context** — pure story beat; `awardsRewards` exists only to satisfy hosts. Win modal buttons: PLAY AGAIN / CONTINUE; loss modal: PLAY AGAIN / EXIT (both routed via `playAgainBtn`/`exitBtn`; EXIT reports `didWin`).

**Tutorial key** — `TutorialManager.kickball` (`"tutorial.kickball.v1"`); included in `allKeys`.

### Mop Bucket Chase

`MopBucketChaseScene` is the Chapter 3 chase: Billy punches Jack and bolts down a hallway mid bucket-race; Jack rows after him — one foot in a rolling mop bucket. Side-scrolling rhythm game, center-origin, manual physics in `update()` (dt-based, so pause needs no clock shifting).

**Stroke loop** — HOLD plants the mop (power builds over `holdFullPower = 0.6 s`; holding past `holdDragStart = 0.85 s` drags: power decays and glide friction more than doubles). RELEASE fires the stroke (impulse scales with power). GLIDE decays speed exponentially (`frictionK = 0.55`). Cadence rule in `releaseStroke()`: a stroke released while `jackSpeed > optHigh` is "TOO EARLY!" (×0.55 impulse); a full-power stroke released inside the `[optLow, optHigh]` band is a "PERFECT STROKE!". All speed/length constants scale with scene width (`maxSpeed = W×1.7`, `optLow/optHigh = W×0.35/0.80`, `hallLength = W×17`, Billy base `W×0.9`, head start `W×2.0`, `catchRadius = W×0.35`).

**Cadence meter** (`buildCadenceMeter()`) — vertical hold-power bar (turns red when dragging) + horizontal speed gauge with a green band and needle. After 3 perfect strokes the whole meter fades to `alpha 0.22` (`meterFaded`); the diegetic cue takes over — `wakePulse()` fires a ripple ring whenever glide speed decays down across `optHigh`.

**Scripted rhythm-breakers** (world-anchored zones as fractions of `hallLength`):
- **Limbo mop** (33%) — two kids hold a mop bar; being mid-HOLD inside the zone = "CLIPPED!" (speed ×0.45, once per run).
- **Spray-bottle kid** (55%) — mists the meter overlay (`mistOverlay`) for 2 s.
- **Puddle strip** (72%) — a stroke *released* inside the zone gets ×1.6 impulse ("SUPER STROKE!").

**Billy** — runs at `billyBase` with three scripted stumbles (at 22/45/68% of the hall; ~1.1 s each at near-zero speed) that give mid-skill players catch-up windows. HUD center label shows `GAP <pts>`, turning green inside one screen-width.

**Ending (canon: Jack never catches him)** — closing to `catchRadius` triggers `startFinale()`: input cut, janitor-water ellipse + Becky spawn ahead, Jack slides at max speed with the bucket spinning, then `crashIntoBecky()` (impact stars, screen shake, "CRASH!", heavy haptic) → win modal "CAUGHT UP... TOO FAST / RIGHT INTO BECKY" (PLAY AGAIN / CONTINUE). Billy reaching the far doors first = loss ("BILLY GOT AWAY", PLAY AGAIN / EXIT).

**World layout** — everything world-anchored (lockers, floor dashes, hazards, Billy, Jack, doors) lives in `scrollLayer`; `layoutWorld()` sets `scrollLayer.position.x = jackScreenX - jackDist` each frame so Jack stays fixed at `x = -W×0.24` on screen.

**Entry points:**
- Story: `p1_becky_incident` ("The Punch") → `.miniGame(.mopChase, winID: "p1_chase_crash", loseID: "p1_chase_retry")`; the win module narrates the sweater incident.
- `MiniGamePickerScene` → `"mopChase"` card (`onComplete = { _ in }`).

**No rewards in any context.** **Tutorial key** — `TutorialManager.mopChase` (`"tutorial.mopChase.v1"`); in `allKeys`.

### Story System

`StoryModuleScene` displays story chapter text over a full-screen panel. Body text `fontSize` is capped at `min(14, W / 17)` — keep this value at 14 to match the pixel-art scale.

#### Data model (`StoryData.swift`)

| Type | Purpose |
|------|---------|
| `StoryModule` | One story beat: `id`, `title`, `imageColor`, `text`, `choices[]`, `autoOutcome` |
| `StoryChoice` | A button label + `StoryOutcome` |
| `StoryOutcome` | `.nextModule(id:)` / `.spawnOnMap(StorySpawnConfig)` / `.miniGame(type, winID, loseID)` / `.returnToMenu` |
| `StoryMiniGame` | `.cornholeVs(opponent:)` / `.baseballVs(difficulty:)` / `.beehive` / `.bike` / `.piranha` / `.beachball` / `.jousters` / `.horseRace` / `.wellFlinger` / `.kickball` / `.mopChase` |
| `StorySpawnConfig` | Bundles `x?`, `y?`, `trigger?`, `nextModuleID?`, `flags[]` for a world spawn |
| `StoryFlag` | `dogsEnabled` / `baseballEnabled` / `batFound` / `questAccepted` / `bulliesEnabled` — `baseballEnabled`, `batFound`, and `questAccepted` are legacy (kept because `GameScene` still reads the first two as an OR-fallback; current story content never sets any of the three) |
| `BaseballAIDifficulty` | `standard` (story Becky, free-play generic) / `powerHitter` (free-play Tim) / `greatFielder` (legacy story Tim, unused by current content) / `fastPitcher` (free-play Jen) |

`StoryManager.shared` persists three things to `UserDefaults`:
- `currentModuleID` — which module to show next (key `storyCurrentModuleID_v1`)
- `pendingWorldTrigger` — string GameScene checks on A-press (key `storyWorldTrigger_v1`)
- flags array — set of enabled `StoryFlag` raw values (key `storyFlags_v1`)

`StoryManager.reset()` clears all three keys.

#### World-trigger strings (defined as `StoryManager` static constants)

| Constant | Value | Fires when player A-presses near |
|----------|-------|----------------------------------|
| `triggerCornhole` | `"cornhole_story"` | Any cornhole board tile |
| `triggerBridge` | `"bridge_story"` | Bridge wood tile |
| `triggerCave` | `"cave_story"` | Any cave tile (bypasses `handleCaveInteraction`'s cluster-teleport maze entirely while the trigger is pending) |
| `triggerAppleTree` | `"appletree_story"` | Apple tree tile |
| `triggerBat` | `"bat_story"` | Story bat pickup object — legacy, unused by current content |
| `triggerBaseball` | `"baseball_story"` | Baseball tile — legacy, unused by current content |
| `triggerQuestOffer` | `"quest_offer"` | Baseball tile (quest re-offer) — legacy, unused by current content |

When a trigger fires, `GameScene` clears `pendingWorldTrigger` and calls `launchStoryAtCurrentModule()`, which transitions to `StoryModuleScene.startAtCurrentProgress()`.

#### `StorySpawnConfig` pattern

`spawnOnMap` outcomes set `nextModuleID` on `StoryManager.currentModuleID` and `trigger` on `pendingWorldTrigger` **before** presenting `GameScene`. This means re-entering the world and pressing A near the right object will always resume the story at the correct module, even after a cold relaunch.

#### Bike race routing

`StoryModuleScene` presents `BikeDodgeViewController` modally (not as an SK scene swap). `BikeDodgeViewController.onDismissWithResult: ((Bool) -> Void)?` delivers the win/loss after the VC dismisses, captured from `BikeDodgeScene.onComplete`. `StoryModuleScene.launchMiniGame(.bike)` sets this callback to call `transitionToModule(id:)` directly — no `queuedModuleID` / `didMove` round-trip needed.

#### Baseball AI difficulty

`CornholeBaseballScene.aiDifficulty: BaseballAIDifficulty` (default `.standard`):
- `.powerHitter` — AI hits 35% harder (`aiPowerBoost = 1.35`) and 45% wider (`vxSpread * 0.45`); used for free-play Tim (HUD name still reads "TIM", mapped from the `.tom` `BaseballAISettings.Character` case)
- `.greatFielder` — AI fielder error ±14 pt (vs standard ±38) and 10-frame reaction delay (vs 20); legacy, not used by current story content (was story Tim's difficulty in the old bat-hunting chain)
- `.fastPitcher` — AI pitch travels 1.5× faster (`pitch.vy *= 1.5` in `throwAIPitch()`), so it's harder to time your swing; used for free-play Jen
- `.standard` — the carnival date's baseball-cornhole vs. Becky (`p3_baseball_intro`), and free-roam "subsequent visits" (generic BOT)

**Free-play opponent picker** — when launched from `MiniGamePickerScene` (the `"baseball"` card sets `scene.showOpponentPicker = true`), `CornholeBaseballScene` shows a two-card Bit-Wood picker in `didMove` before play: **JEN — FAST PITCHER** (`.fastPitcher`) and **TIM — POWER HITTER** (`.powerHitter`). `presentOpponentPicker()` builds the cards (named `"baseballOpp_jen"` / `"baseballOpp_tommy"` — internal node names unchanged); `touchesBegan` routes a tap to `selectOpponent(_:)`, which sets `aiDifficulty` and calls `proceedToPlay()` (tutorial-or-start). The **story path leaves `showOpponentPicker == false`** and pre-sets `aiDifficulty` itself, so the picker never appears there.

#### Bee difficulty ramp

`BeeHiveScene` tracks a global fight count in `UserDefaults` key `beeHiveFightCount_v1`. On each launch the speed multiplier is `min(1.0 + count * 0.12, 2.2)`. `dismissScene(playerWon:)` increments the count regardless of outcome.

#### Story bat pickup (legacy)

`GameScene.spawnStoryBatIfNeeded()`/`collectStoryBat()` still exist and are guarded by `pendingWorldTrigger == StoryManager.triggerBat`, but current story content never sets that trigger, so this path is dead code left over from the old bat-hunting chain. Harmless — the guard just never passes.

#### Legacy module migration

`StoryManager.currentModuleID`'s getter checks the raw `UserDefaults` value against `StoryContent.all`; if the saved ID no longer exists (e.g. a player mid-progress in the old Master Board chain: `p1_tom_win`, `p1_bat_found`, `p1_baseball_jen_intro`, `p1_quest_accept`, `p1_bridge_intro`, …), `StoryManager.legacyModuleMap` redirects it to the nearest equivalent checkpoint in the current chain (`p1_jen_win` — "already beat Jenny, heading into the party arc"). Unknown IDs with no mapping fall back to `firstModuleID`.

#### Part 1 module chain

The narrative follows *Cornhole Kings: A tale of friendship and discovering who you are meant to be* — a prologue establishing 12-year-old Jack's summer of '88, then four acts. Every `.miniGame(...)` loss module offers **REMATCH** (retry immediately) / **QUIT** (back to the pre-match narration) choices, mirroring the existing convention; omitted below for brevity.

```
PROLOGUE
p1_intro → p1_kim_call → p1_kim_heartbreak → p1_kickball → [kickball]
  win  → p1_kickball_dream ("it was a dream") → p1_kickball_vision
  lose → p1_kickball_retry (TRY AGAIN / GIVE UP)
p1_kickball_vision ("what actually happened": the miss, the armor vision, Chad)
  → p1_billy_badger → p1_becky_incident ("The Punch") → [mopChase]
    win  → p1_chase_crash (scripted slip into Becky, sweater incident) → p1_birthday
    lose → p1_chase_retry (TRY AGAIN / GIVE UP)

ACT 1 — THE GIFT
p1_birthday → p1_tim_intro → [cornhole vs .tom ("Tim")]
  win → p1_tim_win → p1_last_day → [bike]
    win → p1_race_win → [world: cornhole trigger]
      → p1_jen_intro → [cornhole vs .jenny]
        win → p1_jen_win → [world: bridge trigger] → p2_river_arrive

ACT 2 — THE PARTY
p2_river_arrive → [piranha]
  win → p2_river_win → [world: cave trigger] → p2_herman_intro → [cornhole vs .barnum ("Herman")]
    win → p2_herman_win → p2_party_arrive → [cornhole vs .ricky]
      win → p2_ricky_win → p3_carnival_intro

ACT 3 — THE DATE
p3_carnival_intro → p3_baseball_intro → [baseball vs .standard ("Becky")]
  win → p3_baseball_win → [jousters]
    win → p3_joust_win → [horseRace]
      win → p3_horserace_win → p4_pool_intro

ACT 4 — TIME FOR TIM
p4_pool_intro → [beachball vs Tim]
  win → p4_pool_win → p4_confession (sets dogsEnabled + bulliesEnabled)
    → [world: apple tree trigger] → p4_queen_intro → [cornhole vs .spirit ("Fairy Queen")]
      win → p4_queen_win → p4_ending (— END OF PART 1 —, loops to itself)
```

#### Dog gating

`GameScene.spawnDog()` is guarded by `StoryManager.shared.hasFlag(.dogsEnabled)`. Dogs (and Billy Badger's gang, via `.bulliesEnabled`) are disabled until the `p4_confession` module fires, right before the Fairy Queen finale — matching the source material's "our yard had been taken over by stray dogs and Billy's gang" beat. In free-play (no story progress), dogs never appear unless the flag is set.

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
