// SampleData.swift
#if DEBUG
import CoreLocation
import SwiftData
import UIKit

/// Fills an empty library with sample photos so screens can be checked in the simulator, which has no camera.
/// Development builds only, and only when launched with `-sampleData`.
enum SampleData {
    @MainActor
    static func loadIfRequested(into context: ModelContext) {
        guard CommandLine.arguments.contains("-sampleData"),
              (try? context.fetchCount(FetchDescriptor<PhotoRecord>())) == 0 else {
            return
        }

        let now = Date()
        let samples: [(daysAgo: Double, kind: Kind, status: LocationStatus, accuracy: Double, fixAge: Double, kept: Bool)] = [
            (0.02, .hobbs("1234.5"), .live, 6, 1, false),
            (0.03, .tach("1187.2"), .live, 8, 2, false),
            (0.05, .fuel("38.4"), .live, 11, 1, false),
            (1.1, .hobbs("1231.9"), .lastKnown, 35, 420, false),
            (1.15, .tach("1184.9"), .unavailable, 0, 0, false),
            (3.3, .hobbs("1229.0"), .live, 5, 1, true),
            (3.32, .fuel("41.0"), .denied, 0, 0, false),
            (40, .hobbs("1210.4"), .live, 9, 1, false),
            (200, .tach("1100.0"), .live, 7, 1, true),
            (400, .hobbs("1150.2"), .live, 12, 1, false)
        ]

        for sample in samples {
            let createdAt = now.addingTimeInterval(-sample.daysAgo * 24 * 60 * 60)
            var location: CapturedLocation?
            if sample.status == .live || sample.status == .lastKnown {
                location = CapturedLocation(CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: 47.5301, longitude: -122.3019),
                    altitude: 6,
                    horizontalAccuracy: sample.accuracy,
                    verticalAccuracy: 4,
                    timestamp: createdAt.addingTimeInterval(-sample.fixAge)
                ))
            }
            let fix = LocationFix(status: sample.status, location: location)

            guard let jpeg = sample.kind.render().jpegData(compressionQuality: 0.9),
                  let photoURL = try? AppPhotoStore.saveJPEGToPrivateLibrary(jpeg, createdAt: createdAt, location: location),
                  let thumbURL = try? AppPhotoStore.generateAndSaveThumbnail(for: photoURL) else {
                continue
            }

            let record = PhotoRecord(
                filePath: photoURL.lastPathComponent,
                createdAt: createdAt,
                thumbnailPath: thumbURL.lastPathComponent,
                locationFix: fix,
                captureTimeZoneIdentifier: TimeZone.current.identifier
            )
            record.isKept = sample.kept
            context.insert(record)
        }

        try? context.save()
    }

    private enum Kind {
        case hobbs(String)
        case tach(String)
        case fuel(String)

        func render() -> UIImage {
            let size = CGSize(width: 1200, height: 900)
            return UIGraphicsImageRenderer(size: size).image { context in
                let cg = context.cgContext
                let colors = [UIColor(white: 0.16, alpha: 1).cgColor, UIColor(white: 0.05, alpha: 1).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

                switch self {
                case .hobbs(let value):
                    drawCounter(title: "HOBBS", value: value, tint: .white, in: size)
                case .tach(let value):
                    drawDial(in: size)
                    drawCounter(title: "TACH", value: value, tint: UIColor(white: 0.85, alpha: 1), in: size, compact: true)
                case .fuel(let value):
                    drawReceipt(gallons: value, in: size)
                }
            }
        }

        private func drawCounter(title: String, value: String, tint: UIColor, in size: CGSize, compact: Bool = false) {
            let digits = Array(value)
            let cell = CGSize(width: compact ? 70 : 110, height: compact ? 100 : 160)
            let totalWidth = CGFloat(digits.count) * (cell.width + 8)
            let origin = CGPoint(x: (size.width - totalWidth) / 2, y: compact ? 600 : 340)

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: compact ? 34 : 44, weight: .heavy),
                .foregroundColor: UIColor(white: 0.6, alpha: 1),
                .kern: 8
            ]
            let titleSize = (title as NSString).size(withAttributes: titleAttributes)
            (title as NSString).draw(
                at: CGPoint(x: (size.width - titleSize.width) / 2, y: origin.y - titleSize.height - 24),
                withAttributes: titleAttributes
            )

            for (index, character) in digits.enumerated() {
                let rect = CGRect(
                    x: origin.x + CGFloat(index) * (cell.width + 8),
                    y: origin.y,
                    width: cell.width,
                    height: cell.height
                )
                let isTenths = index == digits.count - 1
                (isTenths ? UIColor.white : UIColor.black).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: cell.height * 0.7, weight: .bold),
                    .foregroundColor: isTenths ? UIColor.black : tint
                ]
                let text = String(character) as NSString
                let textSize = text.size(withAttributes: attributes)
                text.draw(
                    at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
                    withAttributes: attributes
                )
            }
        }

        private func drawDial(in size: CGSize) {
            let center = CGPoint(x: size.width / 2, y: 380)
            let radius: CGFloat = 260

            UIColor(white: 0.02, alpha: 1).setFill()
            UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()

            UIColor(white: 0.9, alpha: 1).setStroke()
            for tick in 0...30 {
                let angle = CGFloat.pi * 0.75 + CGFloat(tick) / 30 * CGFloat.pi * 1.5
                let inner = radius - (tick % 5 == 0 ? 50 : 26)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * (radius - 10), y: center.y + sin(angle) * (radius - 10)))
                path.lineWidth = tick % 5 == 0 ? 8 : 4
                path.stroke()
            }

            UIColor(red: 0.3, green: 0.85, blue: 0.47, alpha: 1).setStroke()
            let greenArc = UIBezierPath(arcCenter: center, radius: radius - 14, startAngle: .pi * 1.55, endAngle: .pi * 1.95, clockwise: true)
            greenArc.lineWidth = 14
            greenArc.stroke()

            let needleAngle = CGFloat.pi * 1.8
            UIColor.white.setStroke()
            let needle = UIBezierPath()
            needle.move(to: center)
            needle.addLine(to: CGPoint(x: center.x + cos(needleAngle) * (radius - 60), y: center.y + sin(needleAngle) * (radius - 60)))
            needle.lineWidth = 10
            needle.lineCapStyle = .round
            needle.stroke()

            UIColor(white: 0.3, alpha: 1).setFill()
            UIBezierPath(arcCenter: center, radius: 22, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
        }

        private func drawReceipt(gallons: String, in size: CGSize) {
            let paper = CGRect(x: 360, y: 60, width: 480, height: 780)
            UIColor(white: 0.95, alpha: 1).setFill()
            UIBezierPath(roundedRect: paper, cornerRadius: 8).fill()

            let lines = ["AVGAS 100LL", "", "PUMP 2", "GALLONS   \(gallons)", "PRICE/GAL 6.89", "", "THANK YOU"]
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .medium),
                .foregroundColor: UIColor(white: 0.15, alpha: 1)
            ]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: paper.minX + 40, y: paper.minY + 60 + CGFloat(index) * 70), withAttributes: attributes)
            }
        }
    }
}
#endif
