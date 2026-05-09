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

### Inventory System

Items scattered in the world can be walked over to collect them. The system has four files:

- **`Item.swift`** — `ItemType` enum (`coin`, `bag`, `star`) with `color`, `displayName`, and `hudSymbol`.
- **`InventoryManager.swift`** — holds `[ItemType: Int]` counts; fires an `onChanged` closure when any item is collected. `GameScene` owns the instance.
- **`CollectibleNode.swift`** — `SKNode` subclass placed in the map's `mapNode`. Draws an 8×8 colored tile + glow ring, bobs gently, and pops/fades out on contact. Physics body is a sensor (`collisionBitMask = 0`, `contactTestBitMask = PlayerNode.categoryBit`). Uses `collectibleBit = 0x1 << 2`.
- **`InventoryHUDNode.swift`** — `SKNode` attached to `cameraNode`. Renders a horizontal row of dark pill slots (colored icon + `×N` count label) in the bottom chrome, vertically centered between the top of the D-pad cross and the stage bottom border. Call `refresh(counts:)` to redraw.

**Collection flow in `GameScene`:**
1. `setupPlayer()` ORs `CollectibleNode.collectibleBit` into the player's `contactTestBitMask`.
2. `spawnCollectibles(in:)` drops items around the player's spawn point after the map loads.
3. `didBegin(_:)` detects the contact, calls `item.collect()`, updates `InventoryManager`, and spawns a floating `+NAME` pickup label via `showPickupText(_:at:)`.

**To add more item types:** add a case to `ItemType`, give it a `color`/`displayName`/`hudSymbol`, and drop `CollectibleNode(type: .newType)` nodes in `spawnCollectibles(in:)`.

### Key Constants

| Symbol | File | Value | Meaning |
|--------|------|-------|---------|
| `worldZoom` | GameScene | 2.0 | Camera zoom multiplier |
| `cornholeBoardGIDRange` | GameScene | 917...920 | GIDs that trigger cornhole mini-game |
| `baseballGIDRange` | GameScene | 921...922 | GIDs that trigger baseball mini-game |
| `treeGIDRange` | GameScene | 923...930 | GIDs that trigger tree climbing |
| `moveSpeed` | PlayerNode | 120.0 | Player world-units per second |
| `totalCycles` / `pitchesPerHalf` | CornholeBaseballScene | 3 / 3 | Baseball game length |
| `collectibleBit` | CollectibleNode | `0x1 << 2` | Physics category for collectible items |
| `enemyBit` | PlayerNode | `0x1 << 3` | Physics category reserved for enemies |

### Asset Notes

- All PNGs and the `.tmx` file must be added to **Copy Bundle Resources** in Xcode. Xcode's "synchronized folders" setting does not copy `.tsx` files, so tilesets are resolved purely from PNGs at runtime.
- `filteringMode = .nearest` is set on every texture and on `SKView.layer.magnificationFilter` to preserve pixel-art crispness.
- The font `PressStart2P-Regular` is used in the baseball HUD — it must be included in the bundle and declared in `Info.plist` under `UIAppFonts`.
