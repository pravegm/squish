import RealityKit
import SwiftUI
import UIKit

/// Bible §5 visual language: warm studio white, graphite press, hydraulic yellow, candy objects.
enum Palette {
    static let backdrop = UIColor(hex: 0xF3EEE6)
    static let graphite = UIColor(hex: 0x2B2D31)
    static let hydraulicYellow = UIColor(hex: 0xFFB81C)
    static let stampRed = UIColor(hex: 0xD7263D)
    static let duckYellow = UIColor(hex: 0xFFD23F)
    static let beakOrange = UIColor(hex: 0xFF8A1F)
    static let bubbleBlue = UIColor(hex: 0xBFE3F2)
    static let steel = UIColor(hex: 0x8A8F98)

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

    static func unlit(_ color: UIColor, opacity: Float = 1) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }
}
