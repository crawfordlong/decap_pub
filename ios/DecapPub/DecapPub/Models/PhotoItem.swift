import UIKit
import Photos

struct PhotoItem: Identifiable {
    let id: String
    let asset: PHAsset?
    var metadata: PhotoMetadata?

    init(id: String, asset: PHAsset?) {
        self.id = id
        self.asset = asset
    }
    
    // Images are now loaded on-demand from ImageCache
    // This prevents memory bloat from storing hundreds of images
}

struct PhotoMetadata {
    var filename: String = "Unknown"
    var creationDate: Date?
    var fileSize: Int64 = 0
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var cameraModel: String?
    var lensModel: String?
    var aperture: Double?
    var shutterSpeed: String?
    var iso: Int?
    var focalLength: Double?
    var location: String?

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var hasExposureInfo: Bool {
        aperture != nil || shutterSpeed != nil || iso != nil
    }
}

struct Album: Identifiable {
    let id: String
    let title: String
    let count: Int
}
