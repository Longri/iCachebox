import CacheboxCore
import MapKit
import UIKit

/// State of the GPS/Free button (Cachebox `MapViewBase.MapState`; WP, Lock and Car are not taken over).
enum MapState: Int {
    /// The map stays where the user moved it; the info panel shows the coordinates of the map center.
    case free = 0
    /// The map follows the own position.
    case gps = 1

    private static let key = "map.state"

    /// The state of the last session (Cachebox `lastMapToggleBtnState`, default Free).
    static var saved: MapState {
        MapState(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .free
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }
}

/// Own position for the map: where, how exact and where the user looks.
struct OwnPosition: Equatable {
    var coordinate: Coordinate
    /// Accuracy in metres.
    var accuracy: Double?
    /// Degrees from north, clockwise; nil without compass and GPS direction.
    var heading: Double?
    /// The heading comes from the compass (red arrow), otherwise from GPS (cyan arrow).
    var isCompass: Bool

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// Annotation of the own position.
final class OwnPositionAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(_ coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

/// The own position as an arrow pointing where the user looks, with the accuracy circle below (Cachebox
/// `MapViewBase.renderPositionMarker`: `arrow-Compass-Trans` or `arrow-GPS-Trans`, `AccuracyDrawable`).
final class OwnPositionView: MKAnnotationView {
    /// Cachebox `GL_UISizes.posMarkerSize` scaled to the size seen in Cachebox on a phone.
    static let size: CGFloat = 34

    private let arrowLayer = CALayer()
    private let accuracyLayer = CAShapeLayer()
    private var isCompass: Bool?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        canShowCallout = false
        isEnabled = false   // taps go to the map and the caches below
        displayPriority = .required
        zPriority = .max   // above the caches, like Cachebox draws it after them
        clipsToBounds = false
        // blue fill (alpha 50/255) and blue ring like `AccuracyDrawable`
        accuracyLayer.fillColor = UIColor(red: 0, green: 0, blue: 1, alpha: 50 / 255).cgColor
        accuracyLayer.strokeColor = UIColor(red: 0, green: 0, blue: 1, alpha: 0.8).cgColor
        accuracyLayer.lineWidth = 1.5
        layer.addSublayer(accuracyLayer)
        arrowLayer.frame = bounds
        arrowLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(arrowLayer)
        isAccessibilityElement = true
        accessibilityLabel = "Eigene Position"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameters:
    ///   - mapHeading: rotation of the map (`MKMapCamera.heading`), the arrow keeps pointing to the real direction.
    ///   - accuracyRadius: accuracy in points; the circle is drawn only if it is larger than the arrow (Cachebox).
    func update(position: OwnPosition, mapHeading: CLLocationDirection, accuracyRadius: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isCompass != position.isCompass {
            isCompass = position.isCompass
            arrowLayer.contents = CacheboxArrow.position(size: Self.size, compass: position.isCompass,
                                                         transparent: true).cgImage
        }
        let angle = ((position.heading ?? 0) - mapHeading) * .pi / 180
        arrowLayer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
        if accuracyRadius > Self.size / 2, accuracyRadius.isFinite {
            let r = min(accuracyRadius, 20_000)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            accuracyLayer.path = UIBezierPath(arcCenter: center, radius: r, startAngle: 0, endAngle: 2 * .pi,
                                              clockwise: true).cgPath
            accuracyLayer.isHidden = false
        } else {
            accuracyLayer.isHidden = true
        }
        CATransaction.commit()
        if let heading = position.heading {
            accessibilityValue = "Blickrichtung \(Int(heading.rounded())) Grad"
        } else {
            accessibilityValue = nil
        }
    }
}

/// Arrows at the edge of the map pointing to the own position and to the selected cache while they are outside the
/// visible area (Cachebox `MapView.renderTargetArrow` for the cache; the arrow for the own position is new).
/// Tapping one moves the map there. Touches elsewhere go through to the map.
final class EdgeArrowsView: UIView {
    let positionArrow = EdgeArrowButton(kind: .position)
    let targetArrow = EdgeArrowButton(kind: .cache)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        addSubview(targetArrow)
        addSubview(positionArrow)   // on top if both point the same way
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        subviews.contains { !$0.isHidden && $0.frame.contains(point) }
    }

    /// - Parameters:
    ///   - area: the part of the map that is not covered by the info panel, buttons and bars.
    ///   - position/target: screen points of the own position and of the selected cache.
    func update(area: CGRect, position: CGPoint?, target: CGPoint?) {
        // a little inside, so that the arrow is not cut at the screen edge (Cachebox: 90 % of the map)
        let inner = area.insetBy(dx: 8, dy: 8)
        positionArrow.place(in: inner, pointingTo: position)
        targetArrow.place(in: inner, pointingTo: target)
    }
}

/// One arrow at the map edge; its tip lies on the edge of the visible area, the arrow points from the middle of
/// the map towards the target (Cachebox `CB_RectF.getIntersection` and `get_angle`).
final class EdgeArrowButton: UIControl {
    let kind: CacheboxArrow.Target
    private let imageLayer = CALayer()
    /// Hit area around the arrow (HIG 44 pt).
    private static let hitSize = CGSize(width: 44, height: 44)

    init(kind: CacheboxArrow.Target) {
        self.kind = kind
        super.init(frame: CGRect(origin: .zero, size: Self.hitSize))
        let size = CacheboxArrow.targetSize
        imageLayer.frame = CGRect(x: (Self.hitSize.width - size.width) / 2, y: (Self.hitSize.height - size.height) / 2,
                                  width: size.width, height: size.height)
        imageLayer.contents = CacheboxArrow.target(kind).cgImage
        imageLayer.contentsScale = UIScreen.main.scale
        imageLayer.shadowColor = UIColor.black.cgColor
        imageLayer.shadowOpacity = 0.35
        imageLayer.shadowRadius = 1.5
        imageLayer.shadowOffset = .zero
        layer.addSublayer(imageLayer)
        isHidden = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = switch kind {
        case .cache: "Zum gewählten Cache"
        case .position: "Zur eigenen Position"
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func place(in area: CGRect, pointingTo point: CGPoint?) {
        guard let point, area.width > 60, area.height > 60, !area.contains(point),
              point.x.isFinite, point.y.isFinite else {
            isHidden = true
            return
        }
        let center = CGPoint(x: area.midX, y: area.midY)
        let dx = point.x - center.x, dy = point.y - center.y
        // where the line from the middle to the target leaves the area
        let tx = dx == 0 ? CGFloat.infinity : (area.width / 2) / abs(dx)
        let ty = dy == 0 ? CGFloat.infinity : (area.height / 2) / abs(dy)
        let t = min(tx, ty)
        let tip = CGPoint(x: center.x + dx * t, y: center.y + dy * t)
        let length = hypot(dx, dy)
        let direction = CGPoint(x: dx / length, y: dy / length)
        let half = CacheboxArrow.targetSize.height / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transform = .identity
        self.center = CGPoint(x: tip.x - direction.x * half, y: tip.y - direction.y * half)
        // the image points up (−y); rotate it into the direction of the target
        transform = CGAffineTransform(rotationAngle: atan2(direction.x, -direction.y))
        CATransaction.commit()
        isHidden = false
    }
}
