//
//  CornholeKings88Tests.swift
//  CornholeKings88Tests
//
//  Created by Jeff Mielke on 5/3/26.
//

import Testing
import SpriteKit
@testable import CornholeKings88

struct CornholeKings88Tests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    /// Loads the real world map and checks the chunked tile hierarchy and the
    /// composited-atlas texture math: every tile sprite must sit inside its
    /// chunk's coverage rect and sample an exactly tile-sized region of the
    /// shared atlas.
    @Test func worldMapTilesResolveFromSharedAtlas() throws {
        let map = try #require(TMXLoader.load(tmxName: "World1"))
        #expect(!map.layerNodes.isEmpty)

        var tileCount = 0
        for (_, layerNode) in map.layerNodes {
            for chunk in layerNode.children {
                let chunk = try #require(chunk as? TMXTileChunk)
                for child in chunk.children {
                    let sprite = try #require(child as? SKSpriteNode)
                    let texture = try #require(sprite.texture)
                    #expect(texture.size() == map.tileSize)
                    // Coverage is in layer space, same space as tile positions.
                    #expect(chunk.coverage.insetBy(dx: -1, dy: -1).contains(sprite.position))
                    tileCount += 1
                }
            }
        }
        #expect(tileCount > 0)
    }

}
