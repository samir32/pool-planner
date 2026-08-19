import MapKit

/// Georeferenced site plan image: a rectangle of `widthM` meters (height from
/// the image aspect ratio) centered on `center`, rotated by `rotationDeg`.
final class SitePlanOverlay: NSObject, MKOverlay {
    let params: SitePlanParams
    let image: UIImage

    init(params: SitePlanParams, image: UIImage) {
        self.params = params
        self.image = image
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: params.center.lat, longitude: params.center.lng)
    }

    /// Ground size in meters (width from params, height from aspect ratio).
    var groundSize: (w: Double, h: Double) {
        let aspect = image.size.height / max(image.size.width, 1)
        return (params.widthM, params.widthM * aspect)
    }

    var boundingMapRect: MKMapRect {
        let centerPt = MKMapPoint(coordinate)
        let metersPerPt = MKMetersPerMapPointAtLatitude(coordinate.latitude)
        let (w, h) = groundSize
        // Half-diagonal covers any rotation.
        let halfDiagPts = (w * w + h * h).squareRoot() / 2 / metersPerPt
        return MKMapRect(
            x: centerPt.x - halfDiagPts, y: centerPt.y - halfDiagPts,
            width: halfDiagPts * 2, height: halfDiagPts * 2
        )
    }
}

final class SitePlanRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? SitePlanOverlay, let cg = overlay.image.cgImage else { return }
        let params = overlay.params
        let centerPt = point(for: MKMapPoint(overlay.coordinate))
        let metersPerPt = MKMetersPerMapPointAtLatitude(overlay.coordinate.latitude)
        let (wM, hM) = overlay.groundSize
        let w = wM / metersPerPt, h = hM / metersPerPt
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)

        context.saveGState()
        context.translateBy(x: centerPt.x, y: centerPt.y)
        // Map-point space has y growing south, so a positive (clockwise on
        // screen) rotation is a positive angle here.
        context.rotate(by: CGFloat(params.rotationDeg) * .pi / 180)
        context.setAlpha(CGFloat(params.opacity))
        if params.whiteBacking {
            context.setFillColor(UIColor.white.cgColor)
            context.fill(rect)
        }
        // CGImage draws flipped in CG coordinates; the rect is centered on the
        // origin, so a vertical flip about the origin rights it in place.
        context.scaleBy(x: 1, y: -1)
        context.draw(cg, in: rect)
        context.restoreGState()
    }
}
