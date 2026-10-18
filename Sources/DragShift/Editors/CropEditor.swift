import SwiftUI

enum CropAspect: String, CaseIterable, Hashable {
    case free = "Free"
    case square = "1:1"
    case fourThree = "4:3"
    case threeFour = "3:4"
    case sixteenNine = "16:9"
    case nineSixteen = "9:16"

    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .threeFour: return 3.0 / 4.0
        case .sixteenNine: return 16.0 / 9.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}

private enum Corner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: isLeft ? rect.minX : rect.maxX, y: isTop ? rect.minY : rect.maxY)
    }
}

struct CropEditor: View {
    let source: URL
    let image: CGImage
    let close: () -> Void

    /// Crop rect in normalized image coordinates (0…1, top-left origin).
    @State private var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var aspect: CropAspect = .free
    @State private var dragStart: CGRect?

    private var imageSize: CGSize { CGSize(width: image.width, height: image.height) }

    var body: some View {
        EditorScaffold(title: "Crop Image", onCancel: close, onSave: save) {
            GeometryReader { geo in
                let fit = fittedRect(imageSize: imageSize, in: geo.size, inset: 16)
                let crop = CGRect(
                    x: fit.minX + rect.minX * fit.width,
                    y: fit.minY + rect.minY * fit.height,
                    width: rect.width * fit.width,
                    height: rect.height * fit.height
                )
                ZStack {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)

                    Path { path in
                        path.addRect(fit)
                        path.addRect(crop)
                    }
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .overlay(ThirdsGrid().stroke(Color.white.opacity(0.45), lineWidth: 0.5))
                        .overlay(Rectangle().stroke(Color.accent, lineWidth: 2))
                        .frame(width: crop.width, height: crop.height)
                        .position(x: crop.midX, y: crop.midY)
                        .gesture(moveGesture(fit: fit))

                    ForEach(Corner.allCases, id: \.self) { corner in
                        Circle()
                            .fill(Color.accent)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .frame(width: 16, height: 16)
                            .position(corner.point(in: crop))
                            .gesture(
                                DragGesture()
                                    .onChanged { resize(corner, by: $0.translation, fit: fit) }
                                    .onEnded { _ in dragStart = nil }
                            )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        } controls: {
            HStack {
                ChipPicker(options: CropAspect.allCases, title: \.rawValue, selection: $aspect)
                Spacer()
                Text("\(Int(rect.width * imageSize.width)) × \(Int(rect.height * imageSize.height))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.ink.opacity(0.6))
            }
            .onChange(of: aspect) { applyAspect($0) }
        }
    }

    private func moveGesture(fit: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil { dragStart = rect }
                guard let start = dragStart else { return }
                var moved = start
                moved.origin.x = clamp(start.minX + value.translation.width / fit.width, 0, 1 - start.width)
                moved.origin.y = clamp(start.minY + value.translation.height / fit.height, 0, 1 - start.height)
                rect = moved
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resize(_ corner: Corner, by translation: CGSize, fit: CGRect) {
        if dragStart == nil { dragStart = rect }
        guard let start = dragStart else { return }
        let fixed = CGPoint(x: corner.isLeft ? start.maxX : start.minX, y: corner.isTop ? start.maxY : start.minY)
        let moving = CGPoint(
            x: (corner.isLeft ? start.minX : start.maxX) + translation.width / fit.width,
            y: (corner.isTop ? start.minY : start.maxY) + translation.height / fit.height
        )
        let availableWidth = corner.isLeft ? fixed.x : 1 - fixed.x
        let availableHeight = corner.isTop ? fixed.y : 1 - fixed.y
        let minSide: CGFloat = 0.04
        var width = clamp(corner.isLeft ? fixed.x - moving.x : moving.x - fixed.x, minSide, max(availableWidth, minSide))
        var height = clamp(corner.isTop ? fixed.y - moving.y : moving.y - fixed.y, minSide, max(availableHeight, minSide))
        if let ratio = aspect.ratio {
            // Normalized height that keeps the pixel aspect ratio for this width.
            let k = imageSize.width / (ratio * imageSize.height)
            height = width * k
            if height > availableHeight {
                height = availableHeight
                width = height / k
            }
        }
        rect = CGRect(
            x: corner.isLeft ? fixed.x - width : fixed.x,
            y: corner.isTop ? fixed.y - height : fixed.y,
            width: width,
            height: height
        )
    }

    private func applyAspect(_ aspect: CropAspect) {
        guard let ratio = aspect.ratio else { return }
        let imageRatio = imageSize.width / imageSize.height
        var width: CGFloat = 1
        var height: CGFloat = 1
        if imageRatio > ratio {
            width = ratio / imageRatio
        } else {
            height = imageRatio / ratio
        }
        withAnimation(.easeOut(duration: 0.2)) {
            rect = CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
        }
    }

    private func save() {
        let pixels = CGRect(
            x: rect.minX * imageSize.width,
            y: rect.minY * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        ).integral
        guard let cropped = image.cropping(to: pixels) else { return }
        if ActionRunner.save(cropped, source: source, suffix: "Cropped") {
            close()
        }
    }
}

private struct ThirdsGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 1...2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3
            let y = rect.minY + rect.height * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}
