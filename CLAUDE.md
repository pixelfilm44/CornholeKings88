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
- `BeachBallCornholeScene` — pool beachball cornhole blitz (launched from MINI GAMES or pool world trigger)

### Coordinate System & Pixel Scaling

`GameViewController` computes an integer zoom factor `n` so that every source pixel maps to exactly `n` device pixels. The resulting scene size in source pixels is passed to `GameScene`. Inside `GameScene`, `worldZoom = 2.0` is applied to the camera scale (`cameraNode.setScale(1.0 / worldZoom)`), making tiles appear at 2× inside the already-scaled scene. The map is authored at 8×8 tile size; the rendered tile size on screen is `8 × n × worldZoom` device pixels.

The visible play area is a square "stage" (`stageSize = scene.width`). Chrome bars above and below the stage hold the HUD (hearts/score) and on-screen controls (D-pad + A/B buttons). `stageWorldSize = stageSize / worldZoom` is the number of world units in one navigable screen.

### Map System

Maps are authored in **Tiled** (.tmx format, CSV encoding) and loaded by `TMXLoader`. The loader:
1. Parses the `.tmx` XML to find tileset references and layer data.
2. Resolves each `.tsx` tileset to its PNG by lowercasing the basename (e.g., `Grass.tsx` → `grass.png`). **Both the .tmx and all PNG files must be in the Xcode target's Copy Bundle Resources phase**; `.tsx` files are not needed at runtime.
3. Builds `SKSpriteNode` tiles for each layer, returned as a `TMXMap` struct containing `layerGIDs` (raw GID grid per layer name) and `layerNodes` (the rendered `SKNode` per layer).

`GameScene` uses `layerGIDs` to detect special tiles (collision, cornhole boards, baseball zones, trees) by GID range rather than by object layers.

### Physics

- `PlayerNode` uses a small circle physics body anchored at the sprite's feet (`center: CGPoint(x: 0, y: -16)`).
- Collision tiles (water, walls) get `SKPhysicsBody(rectangleOf: tileSize)` bodies added in `buildPhysics(from:)`, using `WorldBit` for collision.
- Mini-game scenes run their own hand-rolled physics (bag arc, gravity, board bounce) without using SpriteKit's physics engine.
- Physics category bits: `categoryBit = 0x1 << 0` (player), `worldBit = 0x1 << 1` (terrain), `collectibleBit = 0x1 << 2` (items), `enemyBit = 0x1 << 3` (enemies). When the player is in a tree, `enemyBit` is removed from their collision and contact masks so enemies pass through.

### Player Animation

`PlayerNode` slices a sprite sheet (`player.png`, 48×48 frames, 6 columns × 10 rows) into animation frame arrays keyed by `AnimState` × `Facing`. Left-facing frames are produced by mirroring right-facing frames via `xScale = -1`. z-position is set to `-position.y` each frame for painter's-algorithm depth sorting.

### Tree Climbing

Press A near a tree tile to climb it. While in a tree the player is stationary and safe from enemies (`enemyBit` removed from physics masks). A green leaf canopy is drawn over the player as a visual indicator. Press A again to descend, or use the d-pad — any directional input auto-descends and resumes normal movement. Walking out of tree proximity also auto-descends.

The proximity radius is 20 world units (`treeRadius` in `checkBoardProximity()`). Tree tiles are detected from the `treeGIDRange` constant (currently `923...930`, matching `trees.tsx` firstgid=923, tilecount=8). The `▲A` prompt appears when in range.

**GID overlap warning:** when adding new tilesets, verify their firstgid + tilecount does not overlap with `baseballGIDRange` (921–922) or `treeGIDRange` (923–930). Tiled assigns firstgids sequentially so always check `World1.tmx` after adding a tileset.

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

`CornholeMiniGameScene` supports four opponents selected via `OpponentPickerNode` before the game starts:

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
- `currentRank: String` — returns `"Rookie"` (rank progression system TBD)
- `recordWin()`, `recordLoss()`, `recordCornhole()`, `reset()`

**`StatsScene.swift`** — SpriteKit scene accessible from `MainMenuScene` via the STATS button. Matches the main menu aesthetic (dark background, wood plaque header, iron-panel stat cards, ember particles, CRT overlay). Displays:
- **RECORD** — `W - L` wins and losses
- **CORNHOLES** — lifetime bags through the hole
- **RANK** — current rank string

Navigation: `◄ BACK` strip at top (push-down transition back to `MainMenuScene`). Dim `RESET STATS` in the footer resets all stats and re-presents the scene with updated values.

### Inventory System

Items scattered in the world can be walked over to collect them. The system has four files:

- **`Item.swift`** — `ItemType` enum (`coin`, `bag`, `star`, `honeyBag`, `bombBag`, `magicBag`) with `color`, `displayName`, and `hudSymbol`.
- **`InventoryManager.swift`** — holds `[ItemType: Int]` counts; fires an `onChanged` closure when any item is collected. `GameScene` owns the instance.
- **`CollectibleNode.swift`** — `SKNode` subclass placed in the map's `mapNode`. Draws an 8×8 colored tile + glow ring, bobs gently, and pops/fades out on contact. Physics body is a sensor (`collisionBitMask = 0`, `contactTestBitMask = PlayerNode.categoryBit`). Uses `collectibleBit = 0x1 << 2`.
- **`InventoryHUDNode.swift`** — `SKNode` attached to `cameraNode`. Renders a horizontal row of dark pill slots (colored icon + `×N` count label) in the bottom chrome, vertically centered between the top of the D-pad cross and the stage bottom border. Call `refresh(counts:)` to redraw.

**Collection flow in `GameScene`:**
1. `setupPlayer()` ORs `CollectibleNode.collectibleBit` into the player's `contactTestBitMask`.
2. `spawnCollectibles(in:)` drops items around the player's spawn point after the map loads.
3. `didBegin(_:)` detects the contact, calls `item.collect()`, updates `InventoryManager`, and spawns a floating `+NAME` pickup label via `showPickupText(_:at:)`.

**Special bag items** (earned from boss opponents, usable in any cornhole game):
- **`honeyBag`** — immune to wind and bot knockback; sticks on board contact.
- **`bombBag`** — landing on the board destroys all opponent board bags; landing in the hole destroys all opponent hole bags. Billy can also throw bomb bags (~25% chance). Awarded (3) by beating Billy the Bully.
- **`magicBag`** — physically intercepts opponent board bags on collision (opponent bag destroyed, magic bag keeps moving). Scoring in the hole destroys all opponent bags already scored in the hole this round. Awarded (3) by beating the Tree Spirit.

`GameScene` passes `availableBombBags` / `availableMagicBags` into `CornholeMiniGameScene` before presenting it, then deducts `bombBagsUsed` / `magicBagsUsed` and adds `bombBagsEarned` / `magicBagsEarned` in the `onComplete` closure.

**To add more item types:** add a case to `ItemType`, give it a `color`/`displayName`/`hudSymbol`, and drop `CollectibleNode(type: .newType)` nodes in `spawnCollectibles(in:)`.

### Key Constants

| Symbol | File | Value | Meaning |
|--------|------|-------|---------|
| `worldZoom` | GameScene | 2.0 | Camera zoom multiplier |
| `cornholeBoardGIDRange` | GameScene | 917...920 | GIDs that trigger cornhole mini-game |
| `baseballGIDRange` | GameScene | 921...922 | GIDs that trigger baseball mini-game |
| `treeGIDRange` | GameScene | 923...930 | GIDs that trigger tree climbing |
| `beehiveGIDRange` | GameScene | 931...934 | GIDs that trigger beehive mini-game |
| `poolGIDRange` | GameScene | 935...938 | GIDs that trigger beach-ball cornhole (tileset not yet added) |
| `moveSpeed` | PlayerNode | 120.0 | Player world-units per second |
| `totalCycles` / `pitchesPerHalf` | CornholeBaseballScene | 3 / 3 | Baseball game length |
| `collectibleBit` | CollectibleNode | `0x1 << 2` | Physics category for collectible items |
| `enemyBit` | PlayerNode | `0x1 << 3` | Physics category reserved for enemies |

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
- World trigger — walk near a pool tile (GID 935–938) and press A. No pool tileset exists in `World1.tmx` yet; add one at firstgid=935, tilecount=4 when ready.

**Beachball texture** is drawn programmatically in `BeachBallCornholeScene.makeBeachBallTexture(diameter:)` — no image asset needed.

### Story Module

`StoryModuleScene` displays story chapter text over a full-screen panel. Body text `fontSize` is capped at `min(14, W / 17)` — keep this value at 14 to match the pixel-art scale.

### Asset Notes

- All PNGs and the `.tmx` file must be added to **Copy Bundle Resources** in Xcode. Xcode's "synchronized folders" setting does not copy `.tsx` files, so tilesets are resolved purely from PNGs at runtime.
- `filteringMode = .nearest` is set on every texture and on `SKView.layer.magnificationFilter` to preserve pixel-art crispness.
- The font `PressStart2P-Regular` is used throughout the UI (menus, HUD, stats screen, story module) — it must be included in the bundle and declared in `Info.plist` under `UIAppFonts`.
