import AVFoundation
import CoreGraphics
import Foundation
import Vision

/// Finds who an angle frames and crops tiles around them, so two speakers side by side sit at the same size on
/// the same eye line.
enum CameraAngleFraming {
    /// Faces smaller than this share of the picture are people in the background or on a poster.
    private static let minimumFaceHeight: CGFloat = 0.05
    private static let sampledFrames = 5

    struct Faces: Equatable {
        /// The main face, as a fraction of the upright picture with the origin at the top left.
        let face: CGRect?
        /// How many faces the angle usually shows.
        let count: Int
        /// Where the main face turns, in radians: positive looks toward the picture's right, negative toward its left.
        let yaw: Double?
    }

    /// The faces in a few frames spread over the file. Wide shots show two or more; close-ups one.
    static func faces(url: URL) async -> Faces {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else {
            return Faces(face: nil, count: 0, yaw: nil)
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        var counts: [Int] = []
        var mains: [(rect: CGRect, yaw: Double?)] = []
        for index in 0..<sampledFrames {
            let seconds = duration * (0.2 + 0.6 * Double(index) / Double(max(1, sampledFrames - 1)))
            guard let image = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
            else { continue }
            let found = detectFaces(in: image)
            counts.append(found.count)
            if let main = found.max(by: { $0.rect.height < $1.rect.height }) { mains.append(main) }
        }
        guard !counts.isEmpty else { return Faces(face: nil, count: 0, yaw: nil) }
        let count = counts.sorted()[counts.count / 2]
        guard count == 1, !mains.isEmpty else { return Faces(face: nil, count: count, yaw: nil) }
        func median(_ values: [CGFloat]) -> CGFloat { values.sorted()[values.count / 2] }
        let face = CGRect(x: median(mains.map(\.rect.minX)), y: median(mains.map(\.rect.minY)),
                          width: median(mains.map(\.rect.width)), height: median(mains.map(\.rect.height)))
        let yaws = mains.compactMap(\.yaw).sorted()
        return Faces(face: face, count: count, yaw: yaws.isEmpty ? nil : yaws[yaws.count / 2])
    }

    private static func detectFaces(in image: CGImage) -> [(rect: CGRect, yaw: Double?)] {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { face in
            let box = face.boundingBox
            guard box.height >= minimumFaceHeight else { return nil }
            // Vision measures from the bottom left; the record keeps the top left like every picture editor.
            return (CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height), face.yaw?.doubleValue)
        }
    }

    struct CropRequest {
        let face: CGRect
        let sourceAspectRatio: CGFloat
        let tileAspectRatio: CGFloat
        /// The share of the tile's height the face fills.
        let faceHeight: CGFloat
        /// Where the face's centre sits from the tile's top, as a share of its height.
        let eyeLine: CGFloat
    }

    /// The crop amount and position that put the face where the request asks, in the terms of
    /// `SourceCropGeometry.cropRectangle`: x and y run from -1 to 1 across the room left on each axis, and y counts
    /// up from the bottom of the picture.
    static func crop(_ request: CropRequest) -> (amount: CGPoint, position: CGPoint) {
        let sourceWidth = request.sourceAspectRatio
        let tile = request.tileAspectRatio
        guard sourceWidth > 0, tile > 0, request.face.height > 0, request.faceHeight > 0 else { return (.zero, .zero) }
        let baseHeight = sourceWidth > tile ? 1 : sourceWidth / tile
        let wantedHeight = request.face.height / request.faceHeight
        let amount = SourceCropGeometry.clampedCropAmount(1 - wantedHeight / baseHeight)
        let height = baseHeight * (1 - amount)
        let width = height * tile
        let centerX = request.face.midX * sourceWidth
        let centerFromTop = request.face.midY - request.eyeLine * height + height / 2
        func position(center: CGFloat, size: CGFloat, length: CGFloat) -> CGFloat {
            let slack = (length - size) / 2
            guard slack > 0.0001 else { return 0 }
            return SourceCropGeometry.clampedCropPosition((center - length / 2) / slack)
        }
        return (
            CGPoint(x: amount, y: amount),
            CGPoint(x: position(center: centerX, size: width, length: sourceWidth),
                    y: position(center: 1 - centerFromTop, size: height, length: 1))
        )
    }
}
