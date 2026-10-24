import Foundation
import RealityKit

/// One object's set of procedural maps, any of which may still be missing (a view keeps its plain material until
/// they land).
struct SurfaceMaps {
    var colour: TextureResource?
    var normal: TextureResource?
    var rough: TextureResource?
    /// A fourth map whose meaning is the object's own (the gummy's core, the jelly's caustics).
    var extra: TextureResource?
}

/// The per-object loaders (`SurfaceDetail.texture` builds each map once per session, off the main actor).
@MainActor
extension SurfaceDetail {
    /// Starts (and awaits) an object's shared maps, so they are cached before its view asks (seeded ones, such as a
    /// can's label, are drawn when the view is made).
    static func warm(_ kind: ObjectKind) async {
        switch kind {
        case .rubberDuck:
            let paint = ObjectMeshes.duckPaint()
            _ = await duckBody(paint)
            _ = await duckCreased(paint)
        case .gummyBear:
            _ = await gummy()
            _ = await gummyPad()
        case .jelly:
            _ = await jelly()
        case .sodaCan:
            _ = await canLid()
        case .unsquishable:
            _ = await steel()
        case .cakeSlice:
            _ = await sponge()
            _ = await pipedFrosting()
            _ = await creamStrokes()
        case .egg:
            _ = await eggShell()
            _ = await eggMembrane()
        case .bubbleWrap:
            _ = await bubbleWrap()
        case .crayon:
            _ = await crayonBox()
            _ = await waxSmear()
            _ = await waxSheen()
        case .glassBottle:
            _ = await bottleLabel()
        }
    }

    // MARK: Rubber duck

    static func duckBody(_ paint: DuckPaint) async -> SurfaceMaps {
        async let colour = texture("duck.vinyl.colour", semantic: .color) { SurfaceImages.duckVinyl(paint, creased: false) }
        async let normal = texture("duck.vinyl.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.duckVinylHeight(paint, creased: false), strength: 1.6)
        }
        async let coat = texture("duck.vinyl.coat", semantic: .raw) { SurfaceImages.duckCoat() }
        return await SurfaceMaps(colour: colour, normal: normal, rough: coat)
    }

    /// The crushed duck's vinyl: the same paint with stress-whitened folds, and their grooves.
    static func duckCreased(_ paint: DuckPaint) async -> SurfaceMaps {
        async let colour = texture("duck.vinyl.creased.colour", semantic: .color) { SurfaceImages.duckVinyl(paint, creased: true) }
        async let normal = texture("duck.vinyl.creased.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.duckVinylHeight(paint, creased: true), strength: 1.6)
        }
        return await SurfaceMaps(colour: colour, normal: normal)
    }

    static func duckBeak() async -> TextureResource? {
        await texture("duck.beak.colour", semantic: .color) { SurfaceImages.duckBeak() }
    }

    /// Tileable vinyl orange-peel (flat vinyl: the duck's skirt).
    static func vinylTile() async -> TextureResource? {
        await texture("vinyl.tile.normal", semantic: .normal) { SurfaceImages.normalImage(SurfaceImages.vinylTile(), strength: 1.4) }
    }

    // MARK: Gummy bear

    static func gummy() async -> SurfaceMaps {
        async let skin = texture("gummy.skin.colour", semantic: .color) { SurfaceImages.gummySkin() }
        async let sugar = texture("gummy.sugar.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.gummySugar(), strength: 2.2)
        }
        async let rough = texture("gummy.sugar.rough", semantic: .raw) { SurfaceImages.gummyRough() }
        async let core = texture("gummy.core.colour", semantic: .color) { SurfaceImages.gummyCore() }
        return await SurfaceMaps(colour: skin, normal: sugar, rough: rough, extra: core)
    }

    static func gummyPad() async -> SurfaceMaps {
        async let colour = texture("gummy.pad.colour", semantic: .color) { SurfaceImages.gummyPad() }
        async let normal = texture("gummy.pad.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.gummyPadHeight(), strength: 1.4)
        }
        return await SurfaceMaps(colour: colour, normal: normal)
    }

    // MARK: Jelly

    /// The skin's ripples (normal) and the core's caustics (`extra`, its colour and its glow).
    static func jelly() async -> SurfaceMaps {
        async let skin = texture("jelly.skin.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.jellySkin(), strength: 0.9)
        }
        async let caustics = texture("jelly.core.caustics", semantic: .color) { SurfaceImages.jellyCaustics() }
        return await SurfaceMaps(normal: skin, extra: caustics)
    }

    // MARK: Cake

    static func sponge() async -> SurfaceMaps {
        async let colour = texture("cake.sponge.colour", semantic: .color) { SurfaceImages.spongeCrumb() }
        async let normal = texture("cake.sponge.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.spongeHeight(), strength: 1.8)
        }
        return await SurfaceMaps(colour: colour, normal: normal)
    }

    static func spongeSmeared(filling: UInt32) async -> TextureResource? {
        await texture("cake.sponge.smeared.\(filling)", semantic: .color) { SurfaceImages.spongeSmeared(filling: filling) }
    }

    static func pipedFrosting() async -> TextureResource? {
        await texture("cake.frosting.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.pipedFrosting(), strength: 2.6)
        }
    }

    static func creamStrokes() async -> TextureResource? {
        await texture("cake.cream.normal", semantic: .normal) { SurfaceImages.normalImage(SurfaceImages.creamStrokes(), strength: 2.0) }
    }

    // MARK: Soda can

    static func canLabel(seed: UInt64) async -> TextureResource? {
        await texture("can.label.fine.\(seed)", semantic: .color) { SurfaceImages.canLabel(seed: 0xF122 &+ seed) }
    }

    static func canLid() async -> SurfaceMaps {
        async let colour = texture("can.lid.colour", semantic: .color) { SurfaceImages.canLidColour() }
        async let normal = texture("can.lid.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.canLidHeight(), strength: 1.6)
        }
        return await SurfaceMaps(colour: colour, normal: normal)
    }

    // MARK: Egg

    static func eggMembrane() async -> SurfaceMaps {
        async let colour = texture("egg.membrane.colour", semantic: .color) { SurfaceImages.eggMembrane() }
        async let normal = texture("egg.membrane.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.eggFibres(), strength: 1.6)
        }
        return await SurfaceMaps(colour: colour, normal: normal)
    }

    // MARK: Bubble wrap

    /// The film's creases (`normal`), the craters' crinkle (`extra`) and the domes' air-cushion light (`colour`).
    static func bubbleWrap() async -> SurfaceMaps {
        async let film = texture("bubble.film.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.filmCreases(), strength: 1.2)
        }
        async let crater = texture("bubble.crater.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.craterCrinkle(), strength: 2.4)
        }
        async let light = texture("bubble.dome.light", semantic: .color) { SurfaceImages.domeLight() }
        return await SurfaceMaps(colour: light, normal: film, extra: crater)
    }

    // MARK: Crayon box

    static func crayonBox() async -> (front: TextureResource?, end: TextureResource?, kraft: TextureResource?) {
        async let front = texture("crayonbox.print.front", semantic: .color) { SurfaceImages.crayonBoxFront() }
        async let end = texture("crayonbox.print.end", semantic: .color) { SurfaceImages.crayonBoxEnd() }
        async let kraft = texture("crayonbox.kraft", semantic: .color) { SurfaceImages.kraft() }
        return await (front, end, kraft)
    }

    static func crayonWrap(band: UInt32, name: String) async -> TextureResource? {
        await texture("crayonbox.wrap.fine.\(band)", semantic: .color) { SurfaceImages.crayonWrap(band: band, name: name) }
    }

    static func waxSheen() async -> TextureResource? {
        await texture("crayonbox.wax.sheen", semantic: .raw) { SurfaceImages.waxSheen() }
    }

    static func waxSmear() async -> SurfaceMaps {
        async let colour = texture("crayonbox.smear.colour", semantic: .color) { SurfaceImages.waxSmear() }
        async let normal = texture("crayonbox.smear.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.waxSmearHeight(), strength: 1.6)
        }
        return await SurfaceMaps(colour: colour, normal: normal)
    }

    // MARK: The Unsquishable

    static func steel() async -> SurfaceMaps {
        async let normal = texture("steel.machined.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.machinedSteel(), strength: 0.5)
        }
        async let rough = texture("steel.breakup", semantic: .raw) { SurfaceImages.steelBreakup() }
        return await SurfaceMaps(normal: normal, rough: rough)
    }
}
