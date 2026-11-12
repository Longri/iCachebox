import UIKit

/// Cachebox `ZoomButtons` on the map: two halves of a pill at the bottom right, zoom out on the left and zoom in on
/// the right. Drawn as vectors after the skin sprites `day-btn-zoom-down/up-normal/-pressed/-disabled` (79 × 48 px,
/// too small for @3x): olive and 85 % opaque, yellow while pressed, pale and lighter where the map cannot zoom further.
/// Like Cachebox (`timeToFadeOut`) they fade after 13 s without a touch on the map and come back with the next one;
/// they also work while faded. Cachebox fades to a quarter (`setMinimumFadeValue(0.25)`), here to 40 %, which the
/// user found easier to see.
final class ZoomButtonsView: UIView {
    let zoomOut = ZoomButton(direction: .out)
    let zoomIn = ZoomButton(direction: .in)

    /// One half; the pair is twice as wide plus the gap.
    static let buttonSize = CGSize(width: 70, height: 46)
    private static let gap: CGFloat = 2
    private static let fadeDelay: TimeInterval = 13
    private static let fadedAlpha: CGFloat = 0.4
    private var fadeTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(zoomOut)
        addSubview(zoomIn)
        wake()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: 2 * Self.buttonSize.width + Self.gap, height: Self.buttonSize.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = Self.buttonSize
        zoomOut.frame = CGRect(origin: .zero, size: size)
        zoomIn.frame = CGRect(origin: CGPoint(x: size.width + Self.gap, y: 0), size: size)
    }

    /// Shows the buttons fully and starts the time until they fade (Cachebox `resetFadeOut`).
    func wake() {
        fadeTimer?.invalidate()
        if alpha < 1 {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.alpha = 1
            }
        }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: Self.fadeDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
    }

    private func fadeOut() {
        UIView.animate(withDuration: 1, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.alpha = Self.fadedAlpha
        }
    }

    /// Enables the halves for the zoom level of the map (Cachebox: disabled sprite at `minzoom`/`maxzoom`).
    func update(zoomLevel: Double, range: ClosedRange<Double>) {
        let canZoomOut = zoomLevel > range.lowerBound + 0.01
        let canZoomIn = zoomLevel < range.upperBound - 0.01
        if zoomOut.isEnabled != canZoomOut { zoomOut.isEnabled = canZoomOut }
        if zoomIn.isEnabled != canZoomIn { zoomIn.isEnabled = canZoomIn }
    }
}

/// One half of `ZoomButtonsView`: rounded on the outer side, with a magnifier there.
final class ZoomButton: UIControl {
    enum Direction { case `in`, out }

    let direction: Direction
    private let icon = UIImageView()

    // sampled from the sprites (premultiplied values converted back)
    private static let normal = UIColor(red: 88 / 255, green: 114 / 255, blue: 23 / 255, alpha: 0.85)
    private static let pressed = UIColor(red: 1, green: 210 / 255, blue: 64 / 255, alpha: 1)
    private static let disabled = UIColor(red: 171 / 255, green: 181 / 255, blue: 147 / 255, alpha: 0.8)

    init(direction: Direction) {
        self.direction = direction
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        let symbol = direction == .in ? "plus.magnifyingglass" : "minus.magnifyingglass"
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22,
                                                                                               weight: .bold))
        icon.tintColor = .black
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        addSubview(icon)
        isAccessibilityElement = true
        accessibilityLabel = direction == .in ? "Hineinzoomen" : "Herauszoomen"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { setNeedsDisplay() } }
    }

    override var isEnabled: Bool {
        didSet {
            setNeedsDisplay()
            icon.alpha = isEnabled ? 1 : 0.35
            accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // the magnifier sits at the rounded end, like on the sprites
        let side = bounds.height
        let x = direction == .in ? bounds.maxX - side * 0.5 - 6 : side * 0.5 + 6
        icon.frame = CGRect(x: x - side / 2, y: (bounds.height - side) / 2 - 1, width: side, height: side)
    }

    /// A slightly larger hit area than the drawn button (the buttons are only 46 pt high).
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -2, dy: -4).contains(point)
    }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        // room for the shadow below (the sprites have a dark band under the button)
        let body = bounds.inset(by: UIEdgeInsets(top: 1, left: 1, bottom: 4, right: 1))
        let path = shape(in: body)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 2, color: UIColor.black.withAlphaComponent(0.3).cgColor)
        let fill = !isEnabled ? Self.disabled : isHighlighted ? Self.pressed : Self.normal
        fill.setFill()
        path.fill()
        cg.restoreGState()
        UIColor.black.withAlphaComponent(isEnabled ? 0.55 : 0.3).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// Half a pill: the outer side round, the inner side with small corners.
    private func shape(in rect: CGRect) -> UIBezierPath {
        let round = rect.height / 2
        let small: CGFloat = 3
        let corners: (topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat) =
            direction == .in ? (small, round, round, small) : (round, small, small, round)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + corners.topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corners.topRight, y: rect.minY))
        path.addArc(withCenter: CGPoint(x: rect.maxX - corners.topRight, y: rect.minY + corners.topRight),
                    radius: corners.topRight, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corners.bottomRight))
        path.addArc(withCenter: CGPoint(x: rect.maxX - corners.bottomRight, y: rect.maxY - corners.bottomRight),
                    radius: corners.bottomRight, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + corners.bottomLeft, y: rect.maxY))
        path.addArc(withCenter: CGPoint(x: rect.minX + corners.bottomLeft, y: rect.maxY - corners.bottomLeft),
                    radius: corners.bottomLeft, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corners.topLeft))
        path.addArc(withCenter: CGPoint(x: rect.minX + corners.topLeft, y: rect.minY + corners.topLeft),
                    radius: corners.topLeft, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: true)
        path.close()
        return path
    }
}
