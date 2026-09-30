import AppKit

enum MenuRainParameter: String, CaseIterable {
    case amount, angle, length, thickness, variation, splash, hue

    var storageKey: String { "MenuEffect.rain.\(rawValue)" }

    var title: String {
        switch self {
        case .amount: "Amount"
        case .angle: "Angle"
        case .length: "Streak length"
        case .thickness: "Thickness"
        case .variation: "Length variation"
        case .splash: "Splash opacity"
        case .hue: "Hue"
        }
    }

    var defaultValue: Double {
        switch self {
        case .amount: 0.05298026424313051
        case .angle: -11.3339309305462
        case .length: 28.02502600080627
        case .thickness: 3.3
        case .variation: 0.5424405742543583
        case .splash: 0.4437146347736625
        case .hue: (4 + (0.3080240885416666 - 0.7840954065322876) / (1 - 0.3080240885416666)) / 6
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .angle: -60...60
        case .length: 2...80
        case .thickness: 0.5...6
        default: 0...1
        }
    }

    var value: Double {
        UserDefaults.standard.object(forKey: storageKey) as? Double ?? defaultValue
    }

    func display(_ value: Double) -> String {
        switch self {
        case .angle: String(format: "%.0f°", value)
        case .length, .thickness: String(format: "%.1f pt", value)
        case .hue: value == 1 ? "White" : String(format: "%.0f°", value * 360)
        default: String(format: "%.0f%%", value * 100)
        }
    }
}

// Streak geometry, density, and splash physics adapted from RainBar.
struct MenuRainSettings {
    let opacity: Double
    let splashOpacity: Double
    let speedMultiplier: Double
    let rainAmount = MenuRainParameter.amount.value
    let speed = 1.993815104166667
    let trailLength = MenuRainParameter.length.value
    let trailLengthVariation = MenuRainParameter.variation.value
    let trailThickness = MenuRainParameter.thickness.value
    let angle = MenuRainParameter.angle.value
    let rainColor: (red: Double, green: Double, blue: Double)

    init(speedMultiplier: Double, brightness: Double) {
        self.speedMultiplier = speedMultiplier
        opacity = min(1, 0.09947144905738735 * brightness)
        splashOpacity = min(1, MenuRainParameter.splash.value * brightness)
        let hue = MenuRainParameter.hue.value
        let color = NSColor(calibratedHue: hue, saturation: hue == 1 ? 0 : 1 - 0.3080240885416666, brightness: 1, alpha: 1)
        rainColor = (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
    }
}

@MainActor
final class MenuRainView: NSView {
    private struct Particle {
        var point: CGPoint
        var lengthNoise: CGFloat
    }

    private struct SplashParticle {
        var point: CGPoint
        var velocity: CGSize
        var age: TimeInterval
        var lifetime: TimeInterval
        var radius: CGFloat
    }

    private struct RainMetrics {
        let motionVector: CGSize
        let streakVector: CGSize
        let trailLengthVariation: CGFloat
        let trailThickness: CGFloat
        let alpha: CGFloat
        let splashAlpha: CGFloat

        init(settings: MenuRainSettings) {
            let radians = settings.angle * .pi / 180
            let speed = CGFloat(380 * settings.speed)
            motionVector = CGSize(
                width: CGFloat(sin(radians)) * speed,
                height: CGFloat(cos(radians)) * speed
            )

            let length = CGFloat(settings.trailLength)
            let magnitude = max(hypot(motionVector.width, motionVector.height), 1)
            streakVector = CGSize(
                width: motionVector.width / magnitude * length,
                height: motionVector.height / magnitude * length
            )
            trailLengthVariation = CGFloat(settings.trailLengthVariation)
            trailThickness = CGFloat(settings.trailThickness)
            alpha = CGFloat(settings.opacity)
            splashAlpha = CGFloat(settings.splashOpacity)
        }
    }

    private let settings: MenuRainSettings
    private let metrics: RainMetrics
    private var particles: [Particle] = []
    private var splashes: [SplashParticle] = []
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(settings: MenuRainSettings) {
        self.settings = settings
        metrics = RainMetrics(settings: settings)
        super.init(frame: .zero)
    }

    isolated deinit {
        timer?.invalidate()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopAnimation()
        } else {
            startAnimation()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        ensureParticles()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if !particles.isEmpty {
            NSColor(
                calibratedRed: settings.rainColor.red,
                green: settings.rainColor.green,
                blue: settings.rainColor.blue,
                alpha: metrics.alpha
            ).setStroke()

            let path = NSBezierPath()
            path.lineWidth = metrics.trailThickness
            path.lineCapStyle = .round

            for particle in particles {
                let lengthScale = max(0.2, 1 + particle.lengthNoise * metrics.trailLengthVariation)
                let streakVector = CGSize(
                    width: metrics.streakVector.width * lengthScale,
                    height: metrics.streakVector.height * lengthScale
                )

                path.move(to: NSPoint(
                    x: particle.point.x - streakVector.width / 2,
                    y: particle.point.y - streakVector.height / 2
                ))
                path.line(to: NSPoint(
                    x: particle.point.x + streakVector.width / 2,
                    y: particle.point.y + streakVector.height / 2
                ))
            }

            path.stroke()
        }

        guard !splashes.isEmpty, let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        for splash in splashes {
            let fade = max(0, 1 - splash.age / splash.lifetime)
            context.setFillColor(
                red: settings.rainColor.red,
                green: settings.rainColor.green,
                blue: settings.rainColor.blue,
                alpha: metrics.splashAlpha * CGFloat(fade)
            )
            context.fillEllipse(in: CGRect(
                x: splash.point.x - splash.radius,
                y: splash.point.y - splash.radius,
                width: splash.radius * 2,
                height: splash.radius * 2
            ))
        }
    }

    private func startAnimation() {
        guard timer == nil else {
            return
        }

        lastTick = ProcessInfo.processInfo.systemUptime
        ensureParticles()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = max(0, min(now - lastTick, 1.0 / 20.0)) * settings.speedMultiplier
        lastTick = now

        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        ensureParticles()

        let margins = spawnMargins(metrics: metrics)

        for index in particles.indices {
            particles[index].point.x += metrics.motionVector.width * delta
            particles[index].point.y += metrics.motionVector.height * delta

            if particles[index].point.y > bounds.height {
                addSplash(at: CGPoint(
                    x: particles[index].point.x,
                    y: bounds.height - 2
                ))
                particles[index] = spawnParticle(metrics: metrics)
            } else if particles[index].point.x < -margins.left
                || particles[index].point.x > bounds.width + margins.right {
                particles[index] = spawnParticle(metrics: metrics)
            }
        }

        for index in splashes.indices {
            splashes[index].age += delta
            splashes[index].point.x += splashes[index].velocity.width * delta
            splashes[index].point.y += splashes[index].velocity.height * delta
            splashes[index].velocity.height += 180 * delta
        }
        splashes.removeAll { $0.age >= $0.lifetime }

        needsDisplay = true
    }

    private func addSplash(at point: CGPoint) {
        guard settings.splashOpacity > 0,
              point.x >= 0,
              point.x <= bounds.width else {
            return
        }

        for _ in 0..<3 {
            splashes.append(SplashParticle(
                point: point,
                velocity: CGSize(
                    width: CGFloat.random(in: -42...42),
                    height: CGFloat.random(in: -72 ... -24)
                ),
                age: 0,
                lifetime: TimeInterval.random(in: 0.18...0.34),
                radius: CGFloat.random(in: 1.3...2.8)
            ))
        }

        if splashes.count > 240 {
            splashes.removeFirst(splashes.count - 240)
        }
    }

    private func ensureParticles() {
        guard bounds.width > 0, bounds.height > 0 else {
            particles.removeAll()
            return
        }

        let targetCount: Int
        if settings.rainAmount <= 0 {
            targetCount = 0
        } else {
            let baseCount = max(80, Int(bounds.width * bounds.height / 4_500))
            let rainMultiplier: Double
            if settings.rainAmount <= 0.5 {
                rainMultiplier = 0.05 + settings.rainAmount / 0.5 * 0.95
            } else {
                rainMultiplier = 1.0 + (settings.rainAmount - 0.5) / 0.5 * 0.25
            }
            targetCount = max(4, Int(Double(baseCount) * rainMultiplier))
        }

        if particles.count < targetCount {
            particles.append(contentsOf: (particles.count..<targetCount).map { _ in
                Particle(point: CGPoint(
                    x: CGFloat.random(in: 0...bounds.width),
                    y: CGFloat.random(in: 0...bounds.height)
                ), lengthNoise: CGFloat.random(in: -1...1))
            })
        } else if particles.count > targetCount {
            particles.removeLast(particles.count - targetCount)
        }
    }

    private func spawnParticle(metrics: RainMetrics) -> Particle {
        let margins = spawnMargins(metrics: metrics)

        return Particle(
            point: CGPoint(
                x: CGFloat.random(in: -margins.left...(bounds.width + margins.right)),
                y: CGFloat.random(in: -90...0)
            ),
            lengthNoise: CGFloat.random(in: -1...1)
        )
    }

    private func spawnMargins(metrics: RainMetrics) -> (left: CGFloat, right: CGFloat) {
        let verticalSpeed = max(abs(metrics.motionVector.height), 1)
        let horizontalTravel = abs(metrics.motionVector.width / verticalSpeed * bounds.height)
        let baseMargin: CGFloat = 36
        let leftMargin = metrics.motionVector.width > 0 ? horizontalTravel + baseMargin : baseMargin
        let rightMargin = metrics.motionVector.width < 0 ? horizontalTravel + baseMargin : baseMargin
        return (leftMargin, rightMargin)
    }
}
