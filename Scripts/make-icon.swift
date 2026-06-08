import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "BlitzRecorder.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let masterURL = repoURL.appendingPathComponent("Resources/AppIcon.png")

guard let master = NSImage(contentsOf: masterURL) else {
    throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: masterURL.path])
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func resize(_ image: NSImage, to pixels: Int) -> NSImage {
    let size = NSSize(width: pixels, height: pixels)
    let resized = NSImage(size: size)
    resized.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(origin: .zero, size: size),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    resized.unlockFocus()
    return resized
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let data = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: data),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

for size in sizes {
    try writePNG(resize(master, to: size.pixels), to: outputURL.appendingPathComponent(size.name))
}
