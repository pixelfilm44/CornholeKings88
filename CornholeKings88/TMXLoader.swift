import SpriteKit

struct TMXMap {
    let mapNode: SKNode
    let tileSize: CGSize
    let cols: Int
    let rows: Int
    let sizeInPoints: CGSize
    let layerGIDs: [String: [[Int]]]
    let layerNodes: [String: SKNode]

    func tileCenter(col: Int, row: Int) -> CGPoint {
        CGPoint(
            x: CGFloat(col) * tileSize.width + tileSize.width / 2,
            y: CGFloat(rows - 1 - row) * tileSize.height + tileSize.height / 2
        )
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
        var tilesets: [LoadedTileset] = []
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
            let tw = parser.tileWidth
            let th = parser.tileHeight
            guard tw > 0, th > 0 else {
                print("TMXLoader: invalid map tile size")
                return nil
            }
            let columns = imageWidth / tw
            let rowsInImage = imageHeight / th
            let tileCount = columns * rowsInImage

            let atlas = SKTexture(image: image)
            atlas.filteringMode = .nearest
            tilesets.append(LoadedTileset(
                firstgid: ref.firstgid,
                tileWidth: tw,
                tileHeight: th,
                columns: columns,
                tileCount: tileCount,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                atlas: atlas
            ))
        }
        tilesets.sort { $0.firstgid < $1.firstgid }

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
                    layerNode.addChild(sprite)
                }
            }
            mapNode.addChild(layerNode)
            layerNodes[layer.name] = layerNode
        }

        return TMXMap(
            mapNode: mapNode,
            tileSize: tileSize,
            cols: cols,
            rows: rows,
            sizeInPoints: sizeInPoints,
            layerGIDs: layerGIDs,
            layerNodes: layerNodes
        )
    }

    private static func tilesetFor(gid: Int, tilesets: [LoadedTileset]) -> LoadedTileset? {
        var match: LoadedTileset?
        for ts in tilesets {
            if ts.firstgid <= gid { match = ts } else { break }
        }
        return match
    }

    private static func textureFor(gid: Int, in ts: LoadedTileset) -> SKTexture? {
        let local = gid - ts.firstgid
        guard ts.columns > 0, local >= 0, local < ts.tileCount else { return nil }
        let col = local % ts.columns
        let row = local / ts.columns
        let tw = CGFloat(ts.tileWidth)
        let th = CGFloat(ts.tileHeight)
        let iw = CGFloat(ts.imageWidth)
        let ih = CGFloat(ts.imageHeight)
        // SKTexture rect: normalized, origin bottom-left
        let normX = (CGFloat(col) * tw) / iw
        let normY = 1.0 - (CGFloat(row + 1) * th) / ih
        let normW = tw / iw
        let normH = th / ih
        let rect = CGRect(x: normX, y: normY, width: normW, height: normH)
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
    let firstgid: Int
    let tileWidth: Int
    let tileHeight: Int
    let columns: Int
    let tileCount: Int
    let imageWidth: Int
    let imageHeight: Int
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
