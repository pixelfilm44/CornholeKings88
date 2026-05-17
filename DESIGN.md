# Cornhole Kings 88 — Game Design Document

## Overview

Cornhole Kings 88 is a retro-styled iOS RPG set in an open world where every challenge resolves through a projectile mini-game. The player explores a top-down pixel-art map, encounters characters, and earns special bags by beating increasingly difficult opponents. The visual language is NES-era pixel art with a wood-and-iron UI palette, CRT scanlines, and PressStart2P typography throughout.

---

## Core Loop

```
World Exploration
      ↓
Approach a trigger (cornhole board, beehive, pool, bridge, apple tree, chest, etc.)
      ↓
Play mini-game (6 variants)
      ↓
Win → earn special bag items / advance story
Lose → lose hearts; retry or return to world
      ↓
Use earned bags in future mini-games for strategic advantage
```

The meta-progression is bag inventory. Special bags (honey, bomb, magic, fire) are won from boss opponents and brought into future cornhole matches, creating a skill + strategy loop.

---

## World Map

- **Tile size:** 8×8 source pixels, rendered at 2× zoom (16×16 on screen)
- **Map size:** 100×100 tiles
- **Format:** Tiled TMX (CSV encoding), loaded at runtime via `TMXLoader`
- **Camera:** SpriteKit `SKCameraNode` at `worldZoom = 2.0`; viewport is a square stage with HUD chrome above and below

### Zones and Triggers

World triggers are detected by **tileset name** (case-insensitive `contains`) — not by hardcoded GID ranges — so adding new tilesets in Tiled requires no code changes. The player presses A near a trigger tile to enter the corresponding interaction.

| Tileset name contains | Trigger | Action |
|-----------------------|---------|--------|
| `cornhole`            | Cornhole boards (2×2 groups) | Classic Cornhole (opponent picker) |
| `baseball`            | Baseball field | Beanbag Baseball |
| `tree` (not `apple`)  | Trees | Climb tree (safe zone; no mini-game) |
| `apple`               | Apple tree | Classic Cornhole vs. Tree Spirit (picker skipped) |
| `bee`                 | Beehive | Beehive Battle |
| `pool`                | Pool area | Beach Ball Cornhole |
| `bridge_stone`        | Stone bridge | Beach Ball Cornhole |
| `chest`               | Treasure chest | One-time reward: 50/50 heart refill or dog biscuit |

### Player

- **Sprite sheet:** 48×48-px frames, 6 columns × 10 rows (`player.png`)
- **Animations:** 4-directional walk, idle; left-facing frames are mirrored right-facing
- **Physics:** Small circle body anchored at feet; `moveSpeed = 120` world-units/second
- **Depth sort:** `zPosition = -position.y` each frame (painter's algorithm)

### Enemies

**Dog** — Spawns in the open world (up to 3 concurrent; interval ~7 seconds). Walks toward the player; contact removes 1 heart. Becoming invincible briefly after a hit prevents multi-hit deaths. Enemies pass through the player while in a tree (`enemyBit` removed from physics masks).

**Distraction by dog biscuit:** if the player taps a `dogBiscuit` slot in the inventory HUD, a bone is placed at the player's feet. Any non-fleeing dog within 80 world units claims the nearest unclaimed biscuit, walks to it, and eats for 3 seconds before resuming the chase. Each biscuit can distract one dog; both the biscuit and the dog's interest disappear when eating completes.

---

## Player Stats and Persistence

All persistent state lives in `UserDefaults`.

| System | Manager | Key Data |
|--------|---------|----------|
| Health | `HeartsManager` | `currentHearts`, max 5 |
| Inventory | `InventoryManager` | `[ItemType: Int]` bag counts |
| Cornhole record | `CornholeStatsManager` | `wins`, `losses`, `cornholes` |
| Story progress | `StoryData` / `UserDefaults` | Current module ID |
| Tutorials seen | `TutorialManager` | One key per mini-game |

### Hearts

- Maximum: **5**
- Refill on: cold app launch, world-map game over, replay-after-loss in any heart-draining game, entering a heart-draining game with 0 hearts
- Drain in: world map (dog bites), Bike Dodge (crashes/bag hits), Beehive Battle (bee stings)
- Score-based games (Classic Cornhole, Baseball, Beach Ball, Piranha Bridge) do **not** drain hearts

---

## Mini-Games

### 1. Classic Cornhole

**Type:** Turn-based competitive  
**Entry:** Walk up to a cornhole board in the world and press A, or via Mini-Game Picker

Before the match starts the player selects an opponent from `OpponentPickerNode`. Opponents are laid out in a 2×2 grid (2 regular, 2 boss).

#### Opponents

| Opponent | Win Score | Special Rules | Reward |
|----------|-----------|---------------|--------|
| Tom | 11 | Baseline AI, moderate accuracy | — |
| Jenny | 11 | Slightly tighter aim than Tom | — |
| Billy the Bully ★ | 21 | Forced thunderstorm every round; adaptive difficulty; throws bomb bags (~25%) | 3 bomb bags |
| Tree Spirit ★ | 21 | Drops magic bags vertically from above (50% cornhole / 50% random board position) | 3 magic bags |

**Billy adaptive difficulty:** `billyNoiseFactor` starts from career accuracy (`cornholes / (totalGames × 12)`, clamped `[1.4, 3.8]`). Player wins tighten Billy by −0.12 per round; Billy wins ease him by +0.15. Losing to the Tree Spirit shows a hint: *"SPECIAL BAGS MAY HELP AGAINST SUCH A FOE..."*

**Scoring:** 3 pts for a cornhole, 1 pt for on-board. First to the win score wins the match. Stats recorded to `CornholeStatsManager` on every bag-in-hole and on win/loss.

#### Bag Types

| Bag | Source | Effect |
|-----|--------|--------|
| Standard | Default | Normal physics |
| Honey Bag | Earned (Beehive) | Immune to wind and knockback; sticks on board contact |
| Bomb Bag | Earned (Billy) / Billy throws | On board: destroys all opponent board bags. In hole: destroys all opponent hole bags |
| Magic Bag | Earned (Tree Spirit) | Physically intercepts opponent board bags (opponent bag destroyed, magic keeps moving). In hole: destroys all opponent hole bags scored this round |
| Fire Bag | TBD | Board: burns all other board bags (thrower keeps 1 pt, all others = 0); sets `boardOnFire` for the round. Hole: burns all other cornholes this round (thrower keeps 3 pts, all others = 0). Visual: pulsing red overlay + ember particles + "🔥 BOARD ON FIRE! 🔥" label |

**Fire bag state** is reset each round in `startRound()`. Losing to the Tree Spirit surfaces the special-bag hint to guide new players.

---

### 2. Beach Ball Cornhole

**Type:** Simultaneous blitz  
**Duration:** 2:00 countdown  
**Entry:** Pool or stone-bridge tile (tileset name contains `pool` or `bridge_stone`), or Mini-Game Picker

Both player and AI throw simultaneously with independent 2-second cooldowns. No turns.

**Key differences from Classic:**
- Beach balls bounce off the board surface (`boardRestitution = 0.80`); only the hole scores (1 pt each)
- Board drifts left/right with slow randomized speed; hole position tracks the drift
- AI throws reactively (0.25–0.85 s after player throws) and autonomously (~every 2 s); accuracy rubber-bands with score gap
- `bzVisualScale = 0.35` (vs. 0.50 for beanbags) keeps arcs on screen
- Ball texture is drawn programmatically — no image asset needed

**Win condition:** Most cornholes at buzzer.

---

### 3. Beanbag Baseball

**Type:** Turn-based competitive  
**Structure:** 3 cycles; each cycle = player bats 3 pitches, then AI bats 3 player pitches  
**Entry:** Baseball field tile (tileset name contains `baseball`) or Mini-Game Picker

**Scoring:** Distance of the hit bag (in feet). Longer hit wins the cycle. Win 2 of 3 cycles to win the match.

**AI:** Adaptive pitch placement. SwiftUI `BaseballHUDView` overlaid on the `SKView` as a `UIHostingController`; injected in `didMove(to:)` and removed in `willMove(from:)`.

---

### 4. Bike Dodge

**Type:** Action racing  
**Entry:** Mini-Game Picker (world trigger TBD)  
**Hearts:** Drains universal hearts; does not reset to max on entry

**Setup:** 3-lane top-down road; player races against a pink and a green AI biker to a 5.0-mile finish line.

**Speed system:**
| State | Speed |
|-------|-------|
| Base | 160 |
| Max (no streak) | 360 |
| Max (20s no-crash streak) | +160 bonus |
| Boost | 3.2× current cap |

**Obstacles:** Oncoming cars, jump trucks (launch the player), beanbags thrown by AI racers. Each hit = −1 heart; brief invincibility after each hit. At 0 hearts → game over.

**Pickups:** Hearts (+1), boosts (3.2× speed for a short duration).

**Minimap:** Vertical progress bar on the right edge with colored dots for all 3 racers.

**Pause:** Tap the `pauseIcon` button (far left of HUD ribbon) to freeze the race. Resume from the pause overlay; tutorial accessible from within the overlay.

**Win condition:** Reach the finish line first, or have the most progress when the only remaining racer.

---

### 5. Beehive Battle

**Type:** Action defense  
**Entry:** Beehive tile (tileset name contains `bee`) or Mini-Game Picker  
**Hearts:** Drains universal hearts

10 bees descend in waves (ramping from 1 to 3 concurrent). Player swipes to throw bags upward at bees. Each bee that reaches the bottom stings the player for −1 heart.

**Win condition:** Hit all 10 bees.  
**Inventory:** Honey bags from inventory can be used.  
**Hearts synced back** to `HeartsManager` on exit.

---

### 6. Piranha Bridge

**Type:** Solo precision challenge  
**Entry:** Mini-Game Picker

Throw 8 bags in a vertical line across a river to build a bridge. 12 bags available total. Piranhas swim through the river and destroy placed bags — a fin warning appears before each strike.

**Win condition:** Fill all 8 bridge slots before running out of bags.

---

## Story Mode

`StoryModuleScene` displays chapters with typewriter body text over a full-screen panel. Each chapter can branch to one of four outcomes:

| Outcome | Effect |
|---------|--------|
| Next module | Linear story advance |
| Spawn on map | Drops the player at specific world coordinates |
| Launch mini-game | Win/lose paths diverge to different story branches |
| Return to menu | End of current arc |

**Text cap:** Body font size is capped at `min(14, W / 17)` to match pixel-art scale. Current first module: `"intro_01"`.

---

## Inventory System

Items are scattered in the world and collected by walking over them, or earned from chests / mini-game wins. The HUD shows a pill-row of colored icons with `×N` counts in the bottom chrome.

**Collection flow:**
1. Player walks over a `CollectibleNode` → contact detected via SpriteKit physics
2. `InventoryManager.onChanged` fires
3. Floating `+NAME` pickup label animates from the collection point
4. `InventoryHUDNode.refresh(counts:)` redraws the pill row

**Item types:** `coin`, `bag`, `star`, `honeyBag`, `bombBag`, `magicBag`, `fireBag`, `goldenBag`, `dogBiscuit`.

**Tap-to-place (`dogBiscuit`):** each inventory slot is a named SKNode (`"slot_<rawValue>"`). Tapping a slot routes through `GameScene.handleInventoryTap(_:)`. For `dogBiscuit` this places a bone node at the player's feet; nearby dogs walk over, eat for 3 seconds, and the biscuit disappears. See **Enemies → Dog** for the distraction mechanic.

**To add a new item type:** add a case to `ItemType` with `color`, `displayName`, and `hudSymbol`. If world-collected, drop `CollectibleNode(type: .newType)` in `spawnCollectibles(in:)`. If usable by tapping its inventory slot, add a case in `GameScene.handleInventoryTap(_:)`.

---

## Chests

Tilesets whose name contains `chest` are one-time interactable reward nodes. Walking near a chest and pressing A:

1. Hides the chest sprite at that map cell (across all layers — the tile is gone for the rest of the session)
2. Rolls 50/50:
   - **Heart** — `HeartsManager.shared.gain()` (no-op if already at 5)
   - **Dog Biscuit** — `inventory.collect(.dogBiscuit, count: 1)`
3. Floats a `+ HEART` or `+ DOG BISCUIT` pickup label

Opened-chest positions are tracked in-memory (`openedChestKeys: Set<String>`) and are not persisted to `UserDefaults` — chests reset on app launch.

---

## Tutorial System

Every mini-game shows a 3-step tutorial on first play, blocking all input until complete. Players can replay from the pause overlay or via the `?` HUD button (in-scene).

**Step types:**
- `.card(title:body:)` — centered modal
- `.hint(at:title:body:)` — panel offset from a target point with a pulsing arrow

**Auto-trigger contract:** `didMove(to:)` checks `TutorialManager.shared.hasSeen(key)`. If unseen, `presentTutorial(autoTriggered: true)` runs and gates the normal start path until complete.

**Tutorial keys:** `.bike`, `.cornhole`, `.baseball`, `.beehive`, `.beachball`, `.piranha`

---

## Audio

| Track | Used In |
|-------|---------|
| `CornholeKingsTheme.mp3` | Main menu, world map |
| `RacingMusic.mp3` | Bike Dodge |
| `hit.mp3` | Bag-board contact |
| `hole_score.wav` | Bag-in-hole |
| `round_end.wav` | Round over |
| `rain_start.wav` | Storm activation (Billy) |
| `gopher_pop.wav` | Gopher event |
| `gopher_steal.wav` | Gopher steal event |
| `game_win.wav` | Victory |
| `game_lose.wav` | Defeat |
| `storm.mp3` | Looping storm ambient (Billy fights) |

`LoadingScene.prewarmAudio()` pre-decodes all audio on cold launch via `AVAudioPlayer.prepareToPlay()` and seeds SpriteKit's cache with silent `SKAudioNode` instances. `MusicPlayer` singleton loops background tracks at volume 0.5.

---

## Visual Style

- **Rendering:** `filteringMode = .nearest` on all textures and `SKView.layer.magnificationFilter = .nearest` — pixel-art crispness at all zoom levels
- **Font:** `PressStart2P-Regular` throughout UI, HUD, menus, stats
- **Color palette:**
  - Background panels: `#1a0a04` dark wood-brown
  - Accent / gold trim: `#f0c060`
  - Primary text: gold `#f0c060` or white
  - Hearts: red-orange `#d4441e`
  - Timer: blue `#5a9cd4`
  - Iron/secondary UI: `rgb(0.35, 0.35, 0.35)` with rust accents
- **Effects:** CRT scanline overlay (28% opacity) + vignette; floating ember particles on menus; wood-plaque section headers

---

## Scene Architecture

```
GameViewController (UIViewController)
└── SKView
    └── GameScene (root world scene)
        ├── gameWorld (SKNode) — map layers + player
        │   ├── TMXMap.mapNode — tiled layers
        │   └── PlayerNode
        └── cameraNode (SKCameraNode)

Mini-game scenes replace GameScene entirely:
  previousScene + onComplete closure pattern for return
  GameScene.hasSetup prevents double-init on re-presentation

BikeDodgeScene is hosted inside BikeDodgeViewController
  (modal UIViewController; not an SKScene transition)
```

**Mini-game return contract:**
```swift
var previousScene: SKScene?
var onComplete: ((Bool) -> Void)?
```
The host scene sets both; the mini-game calls `onComplete?(won)` to return.

---

## HUD Layout

**World map HUD** (attached to `cameraNode`):
- Top chrome: hearts display
- Bottom chrome: `InventoryHUDNode` pill row (bag counts), D-pad, A/B buttons

**Cornhole HUD:** Score labels, round indicator, bag-use buttons  
**Bike Dodge HUD ribbon** (44 pt panel at top, above safe area):
- Far left: pause icon button
- Left: distance label (gold)
- Center: heart symbols (red)
- Right: elapsed time (blue)
- Far right: close button (UIKit `UIButton`, outside SKScene)
- Right edge: vertical minimap progress bar

---

## Coordinate System

`GameViewController` computes integer zoom `n` so source pixels map exactly to `n` device pixels. `GameScene` applies `worldZoom = 2.0` to the camera. The visible play area is a square stage; chrome bars above and below hold HUD and controls.

`stageWorldSize = stageSize / worldZoom` — world units visible per screen side.

---

## Known Placeholders / TODO

| Item | Status |
|------|--------|
| Fire bag reward source | TBD |
| Player rank progression | Hardcoded "Rookie"; formula TBD |
| Settings screen | "COMING SOON" in main menu |
| Coins spending mechanic | Coins collected but no shop |
| Explore mode in picker | Locked (`isLocked = true`) |
| Gopher enemy | Referenced in audio; implementation TBD |

---

## Adding a New Mini-Game (Checklist)

1. Create `FooScene.swift` conforming to the `previousScene` / `onComplete` mini-game pattern
2. Add a `static let foo = "tutorial.foo.v1"` key to `TutorialManager`
3. Implement `presentTutorial(autoTriggered:)` with 3 steps in `FooScene`
4. Gate the start path on `TutorialManager.shared.hasSeen(.foo)` in `didMove`
5. Add the `TutorialHelpButton` to the HUD and route in `touchesBegan`
6. Wire entry from `GameScene` (new tileset-name match in `extract*Positions` + A-button handler) and/or `MiniGamePickerScene`
7. Add a card to `MiniGamePickerScene` (check `isLocked`)
8. If heart-draining: sync `HeartsManager` on entry, loss, and replay

## Adding a New Tileset

Tile interactions are matched by **tileset name** (lowercased basename, case-insensitive `contains`) — not by GID range. The whole class of "did Tiled shift my firstgids?" bugs no longer applies.

1. Drop the PNG into `CornholeKings88/Maps/tilesets/` (filename lowercased; e.g. `Apple_Tree.tsx` → `apple_tree.png`).
2. Create or update the `.tsx` in Tiled and place tiles in `World1.tmx`.
3. If you want the tileset to trigger a world interaction, just include the right keyword in the tileset filename:
   - `cornhole` → cornhole boards (2×2 groups)
   - `baseball` → baseball field
   - `tree` (and NOT `apple`) → climbable
   - `apple` → cornhole vs. Tree Spirit
   - `bee` → beehive battle
   - `pool` or `bridge_stone` → beach-ball cornhole
   - `chest` → one-time reward chest
4. Verify the PNG is in Copy Bundle Resources (synchronized folders should pick it up automatically). The `.tsx` files are not used at runtime — `TMXLoader` resolves images from the lowercased basename.

`TMXLoader` exposes `tilesetRanges: [(name, gidRange)]` on `TMXMap` so `GameScene` can ask: "which tile cells belong to a tileset whose name contains `X`?" and act on the result.
