import MapKit
import UIKit

/// Permit-ready export: MKMapSnapshotter satellite base + Core Graphics
/// redraw of every overlay + scale bar, with a compliance summary block
/// underneath. Produces both PNG and PDF in the temporary directory.
@MainActor
enum Exporter {
    struct Input {
        var scene: MapScene
        var sitePlanImage: UIImage?
        var region: MKCoordinateRegion
        var formatter: UnitFormatter
        var report: ComplianceReport?
        var rules: RuleProfile
        var poolSpec: String?
        var address: String
    }

    static func export(_ input: Input) async throws -> [URL] {
        let mapSize = CGSize(width: 1500, height: 1125)
        let options = MKMapSnapshotter.Options()
        options.region = input.region
        options.size = mapSize
        options.mapType = .satellite
        options.showsBuildings = false
        let snapshot = try await MKMapSnapshotter(options: options).start()

        let summary = summaryLines(input: input)
        let summaryHeight = CGFloat(60 + summary.count * 34 + 24)
        let canvas = CGSize(width: mapSize.width, height: mapSize.height + summaryHeight)

        let image = UIGraphicsImageRenderer(size: canvas).image { ctx in
            let cg = ctx.cgContext
            snapshot.image.draw(at: .zero)
            drawScene(input: input, snapshot: snapshot, in: cg)
            drawScaleBar(input: input, snapshot: snapshot, mapSize: mapSize, in: cg)
            drawSummary(lines: summary, input: input, origin: CGPoint(x: 0, y: mapSize.height),
                        width: canvas.width, height: summaryHeight, in: cg)
        }

        let dir = FileManager.default.temporaryDirectory
        let pngURL = dir.appendingPathComponent("Pool Plan.png")
        let pdfURL = dir.appendingPathComponent("Pool Plan.pdf")
        try image.pngData()?.write(to: pngURL, options: .atomic)
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: canvas))
        try pdf.writePDF(to: pdfURL) { ctx in
            ctx.beginPage()
            image.draw(at: .zero)
        }
        return [pdfURL, pngURL]
    }

    // MARK: - Scene drawing

    private static func drawScene(input: Input, snapshot: MKMapSnapshotter.Snapshot, in cg: CGContext) {
        let scene = input.scene
        func pt(_ ll: LatLng) -> CGPoint {
            snapshot.point(for: CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lng))
        }

        // site plan under everything else
        if let params = scene.sitePlan, let image = input.sitePlanImage, let cgImg = image.cgImage {
            let center = pt(params.center)
            let ppm = pointsPerMeter(snapshot: snapshot, near: params.center)
            let aspect = image.size.height / max(image.size.width, 1)
            let w = params.widthM * ppm
            let h = w * aspect
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y)
            cg.rotate(by: CGFloat(params.rotationDeg) * .pi / 180)
            cg.setAlpha(CGFloat(params.opacity))
            if params.whiteBacking {
                cg.setFillColor(UIColor.white.cgColor)
                cg.fill(rect)
            }
            cg.scaleBy(x: 1, y: -1)
            cg.draw(cgImg, in: rect)
            cg.restoreGState()
        }

        func strokePolygon(_ ring: [LatLng], stroke: UIColor, fill: UIColor) {
            guard ring.count >= 3 else { return }
            let path = UIBezierPath()
            path.move(to: pt(ring[0]))
            for p in ring.dropFirst() { path.addLine(to: pt(p)) }
            path.close()
            path.lineWidth = 3
            fill.setFill()
            path.fill()
            stroke.setStroke()
            path.stroke()
        }

        if scene.lot.count >= 3 {
            let color = scene.lotViolating ? Palette.warn : Palette.lot
            strokePolygon(scene.lot, stroke: color, fill: color.withAlphaComponent(0.05))
        }
        for (i, z) in scene.zones.enumerated() where z.points.count >= 3 {
            let viol = scene.zoneViolating.indices.contains(i) && scene.zoneViolating[i]
            let color = viol ? Palette.warn : Palette.zone
            strokePolygon(z.points, stroke: color, fill: color.withAlphaComponent(0.12))
        }
        for (i, s) in scene.structures.enumerated() where s.count >= 3 {
            let viol = scene.structureViolating.indices.contains(i) && scene.structureViolating[i]
            strokePolygon(
                s,
                stroke: viol ? Palette.warn : Palette.structStroke,
                fill: (viol ? Palette.warn : Palette.structFill).withAlphaComponent(0.15)
            )
        }
        if let ring = scene.poolRing {
            strokePolygon(ring, stroke: Palette.poolStroke, fill: Palette.poolFill)
        }

        for c in scene.connectors {
            let color: UIColor
            if c.violating {
                color = Palette.warn
            } else {
                switch c.kind {
                case .lot, .equipmentToLot: color = Palette.lot
                case .structure: color = Palette.structStroke
                case .equipmentToPool: color = Palette.ink
                case .zone: color = Palette.zone
                }
            }
            let path = UIBezierPath()
            path.move(to: pt(c.from))
            path.addLine(to: pt(c.to))
            path.lineWidth = 3
            path.setLineDash([8, 6], count: 2, phase: 0)
            color.setStroke()
            path.stroke()
            let mid = CGPoint(x: (pt(c.from).x + pt(c.to).x) / 2, y: (pt(c.from).y + pt(c.to).y) / 2)
            drawChip(text: input.formatter.distance(c.distM), at: mid, background: color, in: cg)
        }

        if scene.measurePoints.count > 1 {
            let path = UIBezierPath()
            path.move(to: pt(scene.measurePoints[0]))
            for p in scene.measurePoints.dropFirst() { path.addLine(to: pt(p)) }
            path.lineWidth = 4
            path.setLineDash([4, 10], count: 2, phase: 0)
            Palette.measure.setStroke()
            path.stroke()
        }

        for pin in scene.pins {
            let p = pt(pin.position)
            let badge = CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36)
            let color = pin.kind.measured ? Palette.ink : Palette.snap
            cg.setFillColor(color.withAlphaComponent(0.95).cgColor)
            cg.fillEllipse(in: badge)
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(2.5)
            cg.strokeEllipse(in: badge)
            let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            if let symbol = UIImage(systemName: pin.kind.symbolName, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let s = symbol.size
                symbol.draw(at: CGPoint(x: badge.midX - s.width / 2, y: badge.midY - s.height / 2))
            }
        }
    }

    private static func drawChip(text: String, at center: CGPoint, background: UIColor, in cg: CGContext) {
        let font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = CGRect(
            x: center.x - size.width / 2 - 9, y: center.y - size.height / 2 - 5,
            width: size.width + 18, height: size.height + 10
        )
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        background.withAlphaComponent(0.92).setFill()
        path.fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 9, y: rect.minY + 5), withAttributes: attrs)
    }

    private static func pointsPerMeter(snapshot: MKMapSnapshotter.Snapshot, near ll: LatLng) -> Double {
        let a = snapshot.point(for: CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lng))
        let east = Geo.offset(ll, dx: 100, dy: 0)
        let b = snapshot.point(for: CLLocationCoordinate2D(latitude: east.lat, longitude: east.lng))
        return Double(hypot(b.x - a.x, b.y - a.y)) / 100
    }

    // MARK: - Scale bar

    private static func drawScaleBar(
        input: Input, snapshot: MKMapSnapshotter.Snapshot, mapSize: CGSize, in cg: CGContext
    ) {
        let center = LatLng(lat: input.region.center.latitude, lng: input.region.center.longitude)
        let ppm = pointsPerMeter(snapshot: snapshot, near: center)
        guard ppm > 0 else { return }
        // Nice round length around a fifth of the map width.
        let targetM = Double(mapSize.width) / 5 / ppm
        let mag = pow(10, floor(log10(targetM)))
        let niceM = [1.0, 2, 5, 10].map { $0 * mag }.min {
            abs($0 - targetM) < abs($1 - targetM)
        } ?? targetM
        let barW = CGFloat(niceM * ppm)
        let origin = CGPoint(x: 30, y: mapSize.height - 46)

        cg.setFillColor(UIColor(white: 0, alpha: 0.55).cgColor)
        cg.fill(CGRect(x: origin.x - 10, y: origin.y - 30, width: barW + 20, height: 62))
        cg.setFillColor(UIColor.white.cgColor)
        cg.fill(CGRect(x: origin.x, y: origin.y, width: barW, height: 8))
        cg.fill(CGRect(x: origin.x, y: origin.y - 8, width: 3, height: 24))
        cg.fill(CGRect(x: origin.x + barW - 3, y: origin.y - 8, width: 3, height: 24))
        let ft = niceM / Geo.metersPerFoot
        let label = String(format: "%g m  (%.0f ft)", niceM, ft)
        (label as NSString).draw(
            at: CGPoint(x: origin.x, y: origin.y - 28),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
        )
    }

    // MARK: - Summary block

    struct SummaryLine {
        var text: String
        var pass: Bool? // nil = informational
    }

    private static func summaryLines(input: Input) -> [SummaryLine] {
        var lines: [SummaryLine] = []
        if let spec = input.poolSpec {
            lines.append(SummaryLine(text: spec, pass: nil))
        }
        guard let report = input.report else { return lines }
        let f = input.formatter
        let rules = input.rules

        if report.poolCenterInsideLot == false {
            lines.append(SummaryLine(text: "Pool is outside the property outline", pass: false))
        }
        if let setback = rules.propertyLineSetbackM, let gap = report.lotEdgeGaps.first {
            let d = gap.connector.d
            lines.append(SummaryLine(
                text: "Property-line setback ≥ \(f.distance(setback)) — nearest \(f.distance(d))",
                pass: report.poolCenterInsideLot != false && d >= setback
            ))
        }
        if let setback = rules.structureSetbackM {
            let gaps = report.structureGaps.compactMap { $0?.d }
            if let d = gaps.min() {
                lines.append(SummaryLine(
                    text: "Structure setback ≥ \(f.distance(setback)) — nearest \(f.distance(d))",
                    pass: d >= setback
                ))
            }
        }
        if let clearance = rules.equipmentPoolClearanceM {
            let worst = report.equipment.compactMap(\.toPoolM).min()
            if let d = worst {
                lines.append(SummaryLine(
                    text: "Equipment–pool clearance ≥ \(f.distance(clearance)) — nearest \(f.distance(d))",
                    pass: !report.equipment.contains(where: \.poolViolation)
                ))
            }
        }
        for (i, gap) in report.zoneGaps.enumerated() {
            guard let d = gap?.d else { continue }
            let viol = report.zoneViolations.indices.contains(i) && report.zoneViolations[i]
            let zone = input.scene.zones.indices.contains(i) ? input.scene.zones[i] : nil
            let limit = zone?.setbackM.map { " ≥ \(f.distance($0))" } ?? ""
            lines.append(SummaryLine(
                text: "Zone \(i + 1) clearance\(limit) — nearest \(f.distance(d))",
                pass: !viol
            ))
        }
        if let maxPct = rules.maxLotCoveragePct, let pct = report.coveragePct {
            lines.append(SummaryLine(
                text: String(format: "Lot coverage ≤ %.0f%% — pool covers %.1f%%", maxPct, pct),
                pass: !report.coverageViolation
            ))
        }
        if let area = report.lotAreaM2 {
            lines.append(SummaryLine(text: "Lot area \(f.area(area))", pass: nil))
        }
        return lines
    }

    private static func drawSummary(
        lines: [SummaryLine], input: Input, origin: CGPoint, width: CGFloat, height: CGFloat, in cg: CGContext
    ) {
        cg.setFillColor(UIColor.white.cgColor)
        cg.fill(CGRect(x: origin.x, y: origin.y, width: width, height: height))

        let dateText = Date.now.formatted(date: .abbreviated, time: .omitted)
        let site = input.address.isEmpty ? "" : " — \(input.address)"
        let title = "Pool Placement Plan\(site)  ·  \(dateText)"
        (title as NSString).draw(
            at: CGPoint(x: 30, y: origin.y + 18),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
        )

        var y = origin.y + 60
        for line in lines {
            var text = line.text
            var color = UIColor.darkGray
            if let pass = line.pass {
                text = (pass ? "PASS  " : "FAIL  ") + text
                color = pass
                    ? UIColor(red: 0.1, green: 0.5, blue: 0.15, alpha: 1)
                    : Palette.warn
            }
            (text as NSString).draw(
                at: CGPoint(x: 30, y: y),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 21, weight: line.pass == nil ? .regular : .semibold),
                    .foregroundColor: color,
                ]
            )
            y += 34
        }

        let disclaimer = "Planning aid, not a survey. Verify requirements with your local building/zoning authority."
        (disclaimer as NSString).draw(
            at: CGPoint(x: 30, y: origin.y + height - 30),
            withAttributes: [
                .font: UIFont.italicSystemFont(ofSize: 16),
                .foregroundColor: UIColor.gray,
            ]
        )
    }
}
