import Foundation
import RealityKit
import SwiftUI
import UIKit

/// Bible §5 visual language: warm studio white, graphite press, hydraulic yellow, saturated candy objects.
/// Ooze and fillings are *more* saturated than the shells so the surprise core pops (research 03 §3).
enum Palette {
    // World
    static let backdrop = UIColor(hex: 0xF3EEE6)
    static let graphite = UIColor(hex: 0x2B2D31)
    static let hydraulicYellow = UIColor(hex: 0xFFB81C)
    static let stampRed = UIColor(hex: 0xD7263D)
    static let steel = UIColor(hex: 0x8A8F98)
    static let anvilSteel = UIColor(hex: 0xB9BEC6)
    static let plateSteel = UIColor(hex: 0xC9CDD3)
    static let crackDark = UIColor(hex: 0x3A3D44)
    static let spark = UIColor(hex: 0xFFC94D)

    // Candy signature hues (bible §5)
    static let raspberry = UIColor(hex: 0xE8336F)
    static let lime = UIColor(hex: 0x8BD448)
    static let duckYellow = UIColor(hex: 0xFFD23F)
    static let cobalt = UIColor(hex: 0x2F5BEA)
    static let tangerine = UIColor(hex: 0xFF8A1F)
    static let lemon = UIColor(hex: 0xFFE14D)
    static let grape = UIColor(hex: 0x8E5CF0)
    static let aqua = UIColor(hex: 0x37C9C0)
    static let bubblegum = UIColor(hex: 0xFF8FC8)

    // Objects
    static let beakOrange = UIColor(hex: 0xFF8A1F)
    static let bubbleBlue = UIColor(hex: 0xBFE3F2)
    static let eggshell = UIColor(hex: 0xF8E9D2)
    static let yolk = UIColor(hex: 0xFFB000)
    static let albumen = UIColor(hex: 0xFFFDF6)
    static let sponge = UIColor(hex: 0xF4C98A)
    static let frosting = UIColor(hex: 0xFFD6E6)
    static let cream = UIColor(hex: 0xFFF6EA)
    static let jam = UIColor(hex: 0xE01E4F)
    static let candle = UIColor(hex: 0x7FC8FF)
    static let flame = UIColor(hex: 0xFFC233)
    static let aluminium = UIColor(hex: 0xD3D7DD)
    static let fizzAmber = UIColor(hex: 0xF7DE9A)
    static let cherryFizz = UIColor(hex: 0xFF4F7B)
    static let glass = UIColor(hex: 0xA9EBDD)
    static let glassLabel = UIColor(hex: 0xFFF1C9)
    static let paper = UIColor(hex: 0xFFF7E3)
    static let wrapperCream = UIColor(hex: 0xFFF4DC)
    static let ballSteel = UIColor(hex: 0xDCE0E6)
    static let gold = UIColor(hex: 0xF2C250)
    static let goldMessColor = UIColor(hex: 0xF7D36B)
    static let shadowInk = UIColor(hex: 0x3B2F25)
    static let enamelYellow = UIColor(hex: 0xF5A915)
    static let enamelGraphite = UIColor(hex: 0x34373D)
    static let chrome = UIColor(hex: 0xEDEEF0)
    static let brushedSteel = UIColor(hex: 0xBFC3C8)
    static let rubber = UIColor(hex: 0x25262A)
    static let lampGreen = UIColor(hex: 0x39D98A)
    static let lampAmber = UIColor(hex: 0xFFA000)
    static let lampRed = UIColor(hex: 0xFF3B4E)
    static let lampOff = UIColor(hex: 0x6B6E75)
    static let gaugePaper = UIColor(hex: 0xFBF8F1)
    static let inkSecondary = UIColor(hex: 0x5E6067)
    static let inkTertiary = UIColor(hex: 0x85878D)

    /// Toy-chick yellow (a toy, never a living animal; bible §4 content rules).
    static let chick = UIColor(hex: 0xFFE24A)

    /// Sprinkles, confetti and the rainbow core.
    static let rainbow: [UIColor] = [raspberry, tangerine, lemon, lime, aqua, cobalt, grape]

    static var backdropColor: Color { Color(uiColor: backdrop) }
    static var graphiteColor: Color { Color(uiColor: graphite) }
    static var yellowColor: Color { Color(uiColor: hydraulicYellow) }
    static var stampColor: Color { Color(uiColor: stampRed) }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

@MainActor
enum SceneMaterials {
    static func pbr(_ color: UIColor, roughness: Float, metallic: Float = 0, clearcoat: Float = 0,
                    opacity: Float = 1) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        material.clearcoat = .init(floatLiteral: clearcoat)
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    /// Clearcoated enamel / vinyl (VISUAL-TARGET §4.3).
    static func enamel(_ color: UIColor, roughness: Float, clearcoat: Float, clearcoatRoughness: Float,
                       metallic: Float = 0, specular: Float = 0.5, opacity: Float = 1) -> PhysicallyBasedMaterial {
        var material = pbr(color, roughness: roughness, metallic: metallic, clearcoat: clearcoat, opacity: opacity)
        material.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
        material.specular = .init(floatLiteral: specular)
        return material
    }

    /// A lit material with a baked colour texture.
    static func textured(_ texture: TextureResource, roughness: Float, clearcoat: Float = 0,
                         metallic: Float = 0) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        material.clearcoat = .init(floatLiteral: clearcoat)
        return material
    }

    /// Glowing (lamp-on, flame) material that is still lit.
    static func glowing(_ color: UIColor, intensity: Float) -> PhysicallyBasedMaterial {
        var material = enamel(color, roughness: 0.15, clearcoat: 1, clearcoatRoughness: 0.05)
        material.emissiveColor = .init(color: color)
        material.emissiveIntensity = intensity
        return material
    }

    /// A PBR material with a faint self-glow, for translucent candy (fake SSS, research 03 §3).
    static func candy(_ color: UIColor, roughness: Float = 0.18, opacity: Float = 1, glow: Float = 0.12) -> PhysicallyBasedMaterial {
        var material = pbr(color, roughness: roughness, clearcoat: 1, opacity: opacity)
        if glow > 0 {
            material.emissiveColor = .init(color: color)
            material.emissiveIntensity = glow
        }
        return material
    }

    /// Unlit colour. Not tone-mapped by default (decals, glints, sprites must render exactly; VISUAL-REVIEW-1 fix 1).
    static func unlit(_ color: UIColor, opacity: Float = 1, toneMapped: Bool = false) -> UnlitMaterial {
        var material = UnlitMaterial(color: color, applyPostProcessToneMap: toneMapped)
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    /// The Golden variant (1/50): polished gold vinyl.
    static let gold: PhysicallyBasedMaterial = enamel(Palette.gold, roughness: 0.16, clearcoat: 1, clearcoatRoughness: 0.04,
                                                      metallic: 1)
    /// Gold mess (spreads) — VISUAL-TARGET §5 gold variant.
    static let goldMess: PhysicallyBasedMaterial = pbr(UIColor(hex: 0xF7D36B), roughness: 0.2, metallic: 0.6, clearcoat: 0.6)
}

/// Per-press material choices. Golden presses swap every *body* material for gold;
/// surprises keep their own colours so they pop against the gold.
@MainActor
struct Look {
    let golden: Bool

    init(_ variant: PressVariant) {
        golden = variant.isGolden
    }

    /// The object's main surface.
    func body(_ color: UIColor, roughness: Float = 0.3, clearcoat: Float = 0.6, metallic: Float = 0,
              opacity: Float = 1) -> PhysicallyBasedMaterial {
        golden ? SceneMaterials.gold
            : SceneMaterials.pbr(color, roughness: roughness, metallic: metallic, clearcoat: clearcoat, opacity: opacity)
    }

    /// Translucent candy body (jelly, gummy).
    func candy(_ color: UIColor, opacity: Float = 1, glow: Float = 0.12) -> PhysicallyBasedMaterial {
        golden ? SceneMaterials.gold : SceneMaterials.candy(color, opacity: opacity, glow: glow)
    }

    /// The colour particles should use for this body (gold flecks on Golden presses).
    func tint(_ color: UIColor) -> UIColor {
        golden ? Palette.gold : color
    }
}

/// Seeded choice helper.
extension Array {
    func pick(_ rng: inout SplitMix64) -> Element {
        self[Int(rng.next() % UInt64(count))]
    }
}

/// One place for "don't cast into the shadow map" (sweep, decals, glass, glows), so a single line changes
/// if the component's API differs on the CI SDK.
@MainActor
enum ShadowCasting {
    static func off(_ entity: Entity) {
        entity.components.set(DynamicLightShadowComponent(castsShadow: false))
    }

    /// Translucent materials must not cast: the shadow-caster pipeline can't compile programmable blending
    /// ("meshShadowCasterProgrammableBlending … reading from a rendertarget is not supported").
    /// Walks the hierarchy and opts out every model with a transparent material.
    static func offForTranslucent(in entity: Entity) {
        if let model = entity as? ModelEntity, let materials = model.model?.materials, materials.contains(where: { isTranslucent($0) }) {
            off(model)
        }
        for child in entity.children {
            offForTranslucent(in: child)
        }
    }

    static func isTranslucent(_ material: any RealityKit.Material) -> Bool {
        if let pbr = material as? PhysicallyBasedMaterial {
            if case .transparent = pbr.blending { return true }
        }
        if let unlit = material as? UnlitMaterial {
            if case .transparent = unlit.blending { return true }
        }
        return false
    }
}
