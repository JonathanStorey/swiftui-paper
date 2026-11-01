import CoreGraphics

extension Paper {
    /// What the editor lets people create. Set with `.paperFeatures(_:)`.
    public struct Features: Hashable, Sendable {
        public enum Feature: Hashable, Sendable, CaseIterable {
            case drawing, text, images, stickers, shapeFills, shapeStrokes, shapeOpacity, links, loupes
        }

        var features: Swift.Set<Feature>
        public var inks: Swift.Set<Paper.Ink.Kind>
        /// `FeatureSet.colorMaximumLinearExposure`. 1.0 means no HDR ink.
        public var maximumHDRExposure: CGFloat

        public static let latest = Features(
            features: Swift.Set(Feature.allCases),
            inks: Swift.Set(Paper.Ink.Kind.allCases),
            maximumHDRExposure: 1
        )

        func contains(_ feature: Feature) -> Bool {
            features.contains(feature)
        }

        public func removing(_ feature: Feature) -> Features {
            var copy = self
            copy.features.remove(feature)
            return copy
        }

        public func inserting(_ feature: Feature) -> Features {
            var copy = self
            copy.features.insert(feature)
            return copy
        }
    }
}
