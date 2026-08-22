import Foundation

/// A named, fully user-editable set of numeric rules. The app hardcodes no
/// jurisdiction's bylaws: every value here is an example starting point the
/// user must verify with their municipality. `nil` means the rule is off and
/// excluded from compliance readouts.
public struct RuleProfile: Codable, Equatable, Sendable {
    public enum SetbackReference: String, Codable, Sendable {
        /// Measure setbacks to the pool wall (outer shell).
        case poolWall
        /// Measure setbacks to the water's edge.
        case waterEdge
    }

    public var name: String
    /// Pool to property (lot) lines, meters.
    public var propertyLineSetbackM: Double?
    /// Pool to dwelling/accessory structures, meters.
    public var structureSetbackM: Double?
    /// Equipment to pool wall (anti-climb), meters.
    public var equipmentPoolClearanceM: Double?
    /// Equipment to property lines, meters. Off by default.
    public var equipmentLotSetbackM: Double?
    /// Max pool footprint as % of lot area. Off by default.
    public var maxLotCoveragePct: Double?
    public var setbackReference: SetbackReference
    /// How far the wall/coping extends beyond the water line, meters. Only
    /// meaningful when `setbackReference` is `.poolWall`. Optional so older
    /// saved projects still decode.
    public var copingWidthM: Double?

    public init(
        name: String,
        propertyLineSetbackM: Double? = 1.5,
        structureSetbackM: Double? = 1.5,
        equipmentPoolClearanceM: Double? = 1.0,
        equipmentLotSetbackM: Double? = nil,
        maxLotCoveragePct: Double? = nil,
        setbackReference: SetbackReference = .poolWall,
        copingWidthM: Double? = nil
    ) {
        self.name = name
        self.propertyLineSetbackM = propertyLineSetbackM
        self.structureSetbackM = structureSetbackM
        self.equipmentPoolClearanceM = equipmentPoolClearanceM
        self.equipmentLotSetbackM = equipmentLotSetbackM
        self.maxLotCoveragePct = maxLotCoveragePct
        self.setbackReference = setbackReference
        self.copingWidthM = copingWidthM
    }

    /// Extra distance added around the water polygon before measuring, so
    /// setbacks can be taken from the wall/coping edge instead of the water.
    public var measurementInsetM: Double {
        setbackReference == .poolWall ? max(0, copingWidthM ?? 0) : 0
    }

    /// Conservative common starting point, clearly labeled as an example —
    /// never presented as any jurisdiction's actual rule.
    public static let example = RuleProfile(
        name: String(localized: "Example — verify with your municipality")
    )
}
