import SpriteKit

/// Groups a square block of tile sprites so GameScene can hide whole
/// off-screen blocks with one `isHidden` toggle instead of paying render
/// traversal for every tile in the map each frame. The chunk itself sits at
/// the layer origin; its tiles keep their absolute layer-space positions, so
/// existing position-based lookups only need one extra nesting level.
final class TMXTileChunk: SKNode {
    /// Covered area in map/layer coordinates.
    let coverage: CGRect

    init(coverage: CGRect) {
        self.coverage = coverage
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct TMXMap {
    let mapNode: SKNode
    let tileSize: CGSize
    let cols: Int
    let rows: Int
    let sizeInPoints: CGSize
    let layerGIDs: [String: [[Int]]]
    let layerNodes: [String: SKNode]
    /// Each loaded tileset's lowercase basename, GID range, and grid shape.
    let tilesetRanges: [(name: String, gidRange: ClosedRange<Int>, columns: Int, rows: Int)]

    /// Tiles per side of one culling chunk (see `TMXTileChunk`).
    static let chunkCells = 10

    func tileCenter(col: Int, row: Int) -> CGPoint {
        CGPoint(
            x: CGFloat(col) * tileSize.width + tileSize.width / 2,
            y: CGFloat(rows - 1 - row) * tileSize.height + tileSize.height / 2
        )
    }

    /// Hides every chunk whose coverage lies outside `visibleRect` (map
    /// coordinates) and shows the rest. Sprite-level `isHidden` flags set by
    /// GameScene (opened chests, chopped trees, …) are untouched.
    func cullChunks(outside visibleRect: CGRect) {
        for (_, layerNode) in layerNodes {
            for case let chunk as TMXTileChunk in layerNode.children {
                chunk.isHidden = !chunk.coverage.intersects(visibleRect)
            }
        }
    }
}

enum TMXLoader {

    static func load(tmxName: String) -> TMXMap? {
        guard let tmxURL = findInBundle(filename: "\(tmxName).tmx") else {
            print("TMXLoader: \(tmxName).tmx not found in bundle")
            return nil
        }
        let parser = TMXParser()
        guard parser.parse(url: tmxURL) else {
            print("TMXLoader: failed to parse \(tmxURL.lastPathComponent)")
            return nil
        }

        // Tile dimensions assumed uniform across all tilesets in this map (= map.tileWidth/Height).
        // .tsx files aren't bundled by Xcode's synchronized folders, so we infer tileset metadata
        // from the PNG: filename derived by lowercasing the .tsx basename, columns/tileCount by
        // dividing image dimensions by the map's tile size.
        let tw = parser.tileWidth
        let th = parser.tileHeight
        guard tw > 0, th > 0 else {
            print("TMXLoader: invalid map tile size")
            return nil
        }

        // Collect every tileset's PNG first; they're composited below into one
        // shared atlas texture so tiles from different tilesets share a texture
        // and SpriteKit can batch them into the same draw call.
        var pending: [(name: String, firstgid: Int, columns: Int, tileCount: Int,
                       width: Int, height: Int, image: UIImage)] = []
        for ref in parser.tilesetRefs {
            // Tiled writes tileset sources as paths relative to the .tmx file
            // (e.g. "../../../Grass.tsx"). The bundle is flat, so match by the
            // final filename only.
            let tsxFilename = (ref.source as NSString).lastPathComponent
            let tsxBasename = (tsxFilename as NSString).deletingPathExtension
            let pngName = tsxBasename.lowercased() + ".png"
            guard let imageURL = findInBundle(filename: pngName),
                  let image = UIImage(contentsOfFile: imageURL.path) else {
                print("TMXLoader: image \(pngName) (for tileset \(ref.source)) not found in bundle")
                return nil
            }
            let imageWidth = Int(image.size.width)
            let imageHeight = Int(image.size.height)
            let columns = imageWidth / tw
            let rowsInImage = imageHeight / th
            pending.append((
                name: tsxBasename.lowercased(),
                firstgid: ref.firstgid,
                columns: columns,
                tileCount: columns * rowsInImage,
                width: imageWidth,
                height: imageHeight,
                image: image
            ))
        }
        pending.sort { $0.firstgid < $1.firstgid }

        guard let packed = packTilesets(pending.map { ($0.image, $0.width, $0.height) }) else {
            print("TMXLoader: failed to composite tileset atlas")
            return nil
        }
        let tilesets: [LoadedTileset] = pending.enumerated().map { i, p in
            LoadedTileset(
                name: p.name,
                firstgid: p.firstgid,
                tileWidth: tw,
                tileHeight: th,
                columns: p.columns,
                tileCount: p.tileCount,
                originX: Int(packed.origins[i].x),
                originY: Int(packed.origins[i].y),
                atlasWidth: packed.width,
                atlasHeight: packed.height,
                atlas: packed.atlas
            )
        }

        let tileSize = CGSize(width: parser.tileWidth, height: parser.tileHeight)
        let cols = parser.mapWidth
        let rows = parser.mapHeight
        let sizeInPoints = CGSize(width: CGFloat(cols) * tileSize.width,
                                   height: CGFloat(rows) * tileSize.height)

        let mapNode = SKNode()
        mapNode.name = tmxName

        var layerGIDs: [String: [[Int]]] = [:]
        var layerNodes: [String: SKNode] = [:]

        for (layerIndex, layer) in parser.layers.enumerated() {
            let grid = parseCSV(layer.csv, cols: layer.width, rows: layer.height)
            layerGIDs[layer.name] = grid

            let layerNode = SKNode()
            layerNode.name = layer.name
            layerNode.zPosition = CGFloat(layerIndex)

            // Tiles are parented under TMXTileChunk blocks (keyed by chunk grid
            // index) so GameScene can cull whole off-screen blocks cheaply.
            let chunkCells = TMXMap.chunkCells
            let chunkCols = (cols + chunkCells - 1) / chunkCells
            var chunks: [Int: TMXTileChunk] = [:]

            for r in 0..<rows {
                for c in 0..<cols {
                    let raw = grid[r][c]
                    let gid = raw & 0x0FFFFFFF
                    if gid == 0 { continue }
                    guard let ts = tilesetFor(gid: gid, tilesets: tilesets),
                          let texture = textureFor(gid: gid, in: ts) else { continue }

                    let sprite = SKSpriteNode(texture: texture, size: tileSize)
                    sprite.texture?.filteringMode = .nearest
                    sprite.position = CGPoint(
                        x: CGFloat(c) * tileSize.width + tileSize.width / 2,
                        y: CGFloat(rows - 1 - r) * tileSize.height + tileSize.height / 2
                    )
                    // Stash GID so callers can recover which tileset/tile-row this
                    // sprite came from (used for tree-anchor z-sorting in GameScene).
                    sprite.userData = NSMutableDictionary(dictionary: ["gid": gid])

                    let chunkKey = (r / chunkCells) * chunkCols + (c / chunkCells)
                    let chunk: TMXTileChunk
                    if let existing = chunks[chunkKey] {
                        chunk = existing
                    } else {
                        let c0 = (c / chunkCells) * chunkCells
                        let r0 = (r / chunkCells) * chunkCells
                        let c1 = min(cols, c0 + chunkCells)
                        let r1 = min(rows, r0 + chunkCells)
                        // Row 0 is the top of the map, so the row band [r0, r1)
                        // spans y = (rows - r1) * th ..< (rows - r0) * th.
                        chunk = TMXTileChunk(coverage: CGRect(
                            x: CGFloat(c0) * tileSize.width,
                            y: CGFloat(rows - r1) * tileSize.height,
                            width: CGFloat(c1 - c0) * tileSize.width,
                            height: CGFloat(r1 - r0) * tileSize.height
                        ))
                        chunks[chunkKey] = chunk
                        layerNode.addChild(chunk)
                    }
                    chunk.addChild(sprite)
                }
            }
            mapNode.addChild(layerNode)
            layerNodes[layer.name] = layerNode
        }

        let tilesetRanges: [(name: String, gidRange: ClosedRange<Int>, columns: Int, rows: Int)] = tilesets.map { ts in
            let rowsInTileset = ts.columns > 0 ? (ts.tileCount + ts.columns - 1) / ts.columns : 1
            return (name: ts.name,
                    gidRange: ts.firstgid...(ts.firstgid + ts.tileCount - 1),
                    columns: ts.columns,
                    rows: rowsInTileset)
        }

        return TMXMap(
            mapNode: mapNode,
            tileSize: tileSize,
            cols: cols,
            rows: rows,
            sizeInPoints: sizeInPoints,
            layerGIDs: layerGIDs,
            layerNodes: layerNodes,
            tilesetRanges: tilesetRanges
        )
    }

    private static func tilesetFor(gid: Int, tilesets: [LoadedTileset]) -> LoadedTileset? {
        var match: LoadedTileset?
        for ts in tilesets {
            if ts.firstgid <= gid { match = ts } else { break }
        }
        return match
    }

    /// Shelf-packs the tileset images into one atlas image. A 2 px gutter
    /// separates images so nearest-neighbor sampling at a tileset's outer
    /// edge can't bleed into a neighbor. Returns the shared texture, its
    /// pixel size, and each image's top-left origin (input order preserved).
    private static func packTilesets(_ images: [(image: UIImage, width: Int, height: Int)])
        -> (atlas: SKTexture, width: Int, height: Int, origins: [CGPoint])? {
        let gutter = 2
        let maxRowWidth = 1024
        var origins = Array(repeating: CGPoint.zero, count: images.count)
        var x = 0, y = 0, rowHeight = 0, atlasWidth = 0
        for (i, img) in images.enumerated() {
            if x > 0 && x + img.width > maxRowWidth {
                x = 0
                y += rowHeight + gutter
                rowHeight = 0
            }
            origins[i] = CGPoint(x: x, y: y)
            x += img.width + gutter
            rowHeight = max(rowHeight, img.height)
            atlasWidth = max(atlasWidth, x - gutter)
        }
        let atlasHeight = y + rowHeight
        guard atlasWidth > 0, atlasHeight > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: atlasWidth, height: atlasHeight), format: format)
        let composite = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .none
            for (i, img) in images.enumerated() {
                img.image.draw(in: CGRect(origin: origins[i],
                                          size: CGSize(width: img.width, height: img.height)))
            }
        }
        let atlas = SKTexture(image: composite)
        atlas.filteringMode = .nearest
        return (atlas, atlasWidth, atlasHeight, origins)
    }

    private static func textureFor(gid: Int, in ts: LoadedTileset) -> SKTexture? {
        let local = gid - ts.firstgid
        guard ts.columns > 0, local >= 0, local < ts.tileCount else { return nil }
        let col = local % ts.columns
        let row = local / ts.columns
        let tw = CGFloat(ts.tileWidth)
        let th = CGFloat(ts.tileHeight)
        let aw = CGFloat(ts.atlasWidth)
        let ah = CGFloat(ts.atlasHeight)
        // Tile position in atlas pixels, top-left origin…
        let px = CGFloat(ts.originX) + CGFloat(col) * tw
        let pyTop = CGFloat(ts.originY) + CGFloat(row) * th
        // …converted to SKTexture's normalized, bottom-left-origin rect.
        let rect = CGRect(x: px / aw,
                          y: 1.0 - (pyTop + th) / ah,
                          width: tw / aw,
                          height: th / ah)
        let tex = SKTexture(rect: rect, in: ts.atlas)
        tex.filteringMode = .nearest
        return tex
    }

    private static func parseCSV(_ raw: String, cols: Int, rows: Int) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: cols), count: rows)
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = cleaned.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        var r = 0
        for line in lines {
            if r >= rows { break }
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty { continue }
            let parts = trimmedLine.split(separator: ",")
            var c = 0
            for part in parts {
                if c >= cols { break }
                let val = Int(part.trimmingCharacters(in: .whitespaces)) ?? 0
                grid[r][c] = val
                c += 1
            }
            r += 1
        }
        return grid
    }

    private static func findInBundle(filename: String) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        if let enumerator = FileManager.default.enumerator(at: resourceURL,
                                                            includingPropertiesForKeys: nil) {
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent == filename { return url }
            }
        }
        return nil
    }
}

private struct LoadedTileset {
    let name: String
    let firstgid: Int
    let tileWidth: Int
    let tileHeight: Int
    let columns: Int
    let tileCount: Int
    /// Top-left corner of this tileset's image inside the shared atlas, in pixels.
    let originX: Int
    let originY: Int
    let atlasWidth: Int
    let atlasHeight: Int
    /// The composited atlas texture shared by every tileset in the map.
    let atlas: SKTexture
}

// MARK: - XML Parsers

private final class TMXParser: NSObject, XMLParserDelegate {
    var mapWidth = 0
    var mapHeight = 0
    var tileWidth = 0
    var tileHeight = 0
    var tilesetRefs: [(firstgid: Int, source: String)] = []
    var layers: [(name: String, width: Int, height: Int, csv: String)] = []

    private var currentLayer: (name: String, width: Int, height: Int)?
    private var capturingData = false
    private var dataBuffer = ""

    func parse(url: URL) -> Bool {
        guard let parser = XMLParser(contentsOf: url) else { return false }
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "map":
            mapWidth = Int(attributeDict["width"] ?? "0") ?? 0
            mapHeight = Int(attributeDict["height"] ?? "0") ?? 0
            tileWidth = Int(attributeDict["tilewidth"] ?? "0") ?? 0
            tileHeight = Int(attributeDict["tileheight"] ?? "0") ?? 0
        case "tileset":
            if let src = attributeDict["source"],
               let fg = Int(attributeDict["firstgid"] ?? "0") {
                tilesetRefs.append((fg, src))
            }
        case "layer":
            currentLayer = (
                name: attributeDict["name"] ?? "",
                width: Int(attributeDict["width"] ?? "0") ?? 0,
                height: Int(attributeDict["height"] ?? "0") ?? 0
            )
        case "data":
            capturingData = true
            dataBuffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingData { dataBuffer += string }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "data" {
            capturingData = false
            if let l = currentLayer {
                layers.append((l.name, l.width, l.height, dataBuffer))
            }
        }
        if elementName == "layer" {
            currentLayer = nil
        }
    }
}

private final class TSXParser: NSObject, XMLParserDelegate {
    var tileWidth = 0
    var tileHeight = 0
    var columns = 0
    var tileCount = 0
    var imageSource = ""
    var imageWidth = 0
    var imageHeight = 0

    func parse(url: URL) -> Bool {
        guard let parser = XMLParser(contentsOf: url) else { return false }
        parser.delegate = self
        return parser.parse()
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "tileset":
            tileWidth = Int(attributeDict["tilewidth"] ?? "0") ?? 0
            tileHeight = Int(attributeDict["tileheight"] ?? "0") ?? 0
            columns = Int(attributeDict["columns"] ?? "0") ?? 0
            tileCount = Int(attributeDict["tilecount"] ?? "0") ?? 0
        case "image":
            imageSource = attributeDict["source"] ?? ""
            imageWidth = Int(attributeDict["width"] ?? "0") ?? 0
            imageHeight = Int(attributeDict["height"] ?? "0") ?? 0
        default:
            break
        }
    }
}
