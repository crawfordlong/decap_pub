import SwiftUI
import Photos
import UIKit

enum PhotoSource {
    case photoLibrary
    case recents
    case favorites
    case album(String)
    case files
}

@MainActor
class PhotoGalleryViewModel: ObservableObject {
    @Published var photos: [PhotoItem] = []
    @Published var albums: [Album] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var currentSource: PhotoSource = .photoLibrary

    @AppStorage("siteName") var siteName = "Crawford Long"
    @AppStorage("siteEndpoint") private var siteEndpoint = "https://crawfordlong.com"
    @AppStorage("githubRepo") private var githubRepo = "crawfordlong/crawfordlong-com-2025"
    @AppStorage("githubBranch") private var githubBranch = "trunk"
    @AppStorage("contentPath") private var contentPath = "content/photos"

    private let imageManager = PHCachingImageManager()
    private let thumbnailSize = CGSize(width: 600, height: 600)
    
    // Pagination: 60 photos per page (20 rows of 3)
    private let pageSize = 60
    private var currentPage = 0
    private var hasMorePhotos = true
    private var allAssets: PHFetchResult<PHAsset>?
    
    // Memory warning observer
    private var memoryWarningObserver: NSObjectProtocol?
    
    // MARK: - Image Caching with NSCache
    
    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 100 * 1024 * 1024 // 100MB for higher-res thumbnails
        cache.countLimit = 50 // Max 50 thumbnails (larger size)
        return cache
    }()
    
    private let fullImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 200 * 1024 * 1024 // 200MB for full images
        cache.countLimit = 10 // Max 10 full images in memory
        return cache
    }()

    init() {
        loadAlbums()
        setupMemoryWarningHandler()
    }
    
    deinit {
        // Clean up the observer to prevent memory leaks
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupMemoryWarningHandler() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    private func handleMemoryWarning() {
        thumbnailCache.removeAllObjects()
        fullImageCache.removeAllObjects()
    }
    
    func clearImageCache() {
        handleMemoryWarning()
    }

    func loadPhotos() {
        requestPhotoLibraryAccess { [weak self] granted in
            guard granted else { return }
            Task { @MainActor in
                self?.fetchPhotos()
            }
        }
    }

    func selectSource(_ source: PhotoSource) {
        currentSource = source
        fetchPhotos()
    }

    func showFilePicker() {
        // TODO: Implement UIDocumentPickerViewController integration
    }

    func sendToSite(photos: [PhotoItem]) async {
        let token = KeychainManager.shared.githubToken
        guard !token.isEmpty else {
            return
        }

        for photo in photos {
            await uploadPhoto(photo)
        }
    }
    
    // MARK: - Image Loading with NSCache
    
    /// Load thumbnail for a specific photo on-demand
    func loadThumbnail(for photo: PhotoItem) async -> UIImage? {
        let cacheKey = photo.id as NSString
        
        // Check cache first
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }
        
        guard let asset = photo.asset else { return nil }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            
            imageManager.requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, info in
                // Check if this is the final/degraded result
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                
                // Only resume once with the final (non-degraded) image
                guard !hasResumed && !isDegraded else { return }
                hasResumed = true
                
                if let image = image {
                    let cost = Int(image.size.width * image.size.height * 4)
                    self?.thumbnailCache.setObject(image, forKey: cacheKey, cost: cost)
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Load full image for a specific photo on-demand
    func loadFullImage(for photo: PhotoItem) async -> UIImage? {
        let cacheKey = (photo.id + "_full") as NSString
        
        // Check cache first
        if let cached = fullImageCache.object(forKey: cacheKey) {
            return cached
        }
        
        guard let asset = photo.asset else { return nil }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                
                guard !hasResumed && !isDegraded else { return }
                hasResumed = true
                
                if let image = image {
                    let cost = Int(image.size.width * image.size.height * 4)
                    self?.fullImageCache.setObject(image, forKey: cacheKey, cost: cost)
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Load metadata for a specific photo
    func loadMetadata(for photo: PhotoItem) async -> PhotoMetadata? {
        guard let asset = photo.asset else { return nil }
        
        var metadata = PhotoMetadata()
        
        // Load basic metadata
        let resources = PHAssetResource.assetResources(for: asset)
        metadata.filename = resources.first?.originalFilename ?? "Unknown"
        metadata.creationDate = asset.creationDate
        metadata.pixelWidth = asset.pixelWidth
        metadata.pixelHeight = asset.pixelHeight
        
        if let resource = resources.first {
            if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                metadata.fileSize = fileSize
            }
        }
        
        // Get location
        if let location = asset.location {
            metadata.location = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
        }
        
        // Get EXIF data
        let exifData = await withCheckedContinuation { (continuation: CheckedContinuation<(String?, String?, Double?, Int?, Double?, Double?), Never>) in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            
            asset.requestContentEditingInput(with: options) { input, info in
                guard let url = input?.fullSizeImageURL else {
                    continuation.resume(returning: (nil, nil, nil, nil, nil, nil))
                    return
                }
                
                guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
                    continuation.resume(returning: (nil, nil, nil, nil, nil, nil))
                    return
                }
                
                var cameraModel: String?
                var lensModel: String?
                var aperture: Double?
                var iso: Int?
                var focalLength: Double?
                var shutterSpeed: Double?
                
                // TIFF data
                if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                    cameraModel = tiff[kCGImagePropertyTIFFModel as String] as? String
                }
                
                // EXIF data
                if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                    aperture = exif[kCGImagePropertyExifFNumber as String] as? Double
                    iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? Int
                    focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double
                    shutterSpeed = exif[kCGImagePropertyExifExposureTime as String] as? Double
                    lensModel = exif[kCGImagePropertyExifLensModel as String] as? String
                }
                
                continuation.resume(returning: (cameraModel, lensModel, aperture, iso, focalLength, shutterSpeed))
            }
        }
        
        // Apply EXIF data to metadata
        metadata.cameraModel = exifData.0
        metadata.lensModel = exifData.1
        metadata.aperture = exifData.2
        metadata.iso = exifData.3
        metadata.focalLength = exifData.4
        
        if let exposureTime = exifData.5 {
            if exposureTime < 1 {
                metadata.shutterSpeed = "1/\(Int(1/exposureTime))"
            } else {
                metadata.shutterSpeed = "\(exposureTime)s"
            }
        }
        
        return metadata
    }

    // MARK: - Private Methods

    private func requestPhotoLibraryAccess(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            completion(false)
        }
    }

    private func fetchPhotos() {
        isLoading = true
        currentPage = 0
        photos = []
        hasMorePhotos = true

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        switch currentSource {
        case .photoLibrary:
            allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        case .recents:
            if let recents = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil).firstObject {
                allAssets = PHAsset.fetchAssets(in: recents, options: fetchOptions)
            } else {
                allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            }
        case .favorites:
            fetchOptions.predicate = NSPredicate(format: "isFavorite == YES")
            allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        case .album(let albumId):
            let albumOptions = PHFetchOptions()
            albumOptions.predicate = NSPredicate(format: "localIdentifier == %@", albumId)
            if let album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: albumOptions).firstObject {
                allAssets = PHAsset.fetchAssets(in: album, options: fetchOptions)
            } else {
                allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            }
        case .files:
            isLoading = false
            return
        }

        loadNextPage()
    }
    
    func loadNextPage() {
        guard !isLoadingMore, hasMorePhotos, let assets = allAssets else { return }
        
        isLoadingMore = true
        
        let startIndex = currentPage * pageSize
        let endIndex = min(startIndex + pageSize, assets.count)
        
        guard startIndex < assets.count else {
            hasMorePhotos = false
            isLoading = false
            isLoadingMore = false
            return
        }
        
        var newPhotos: [PhotoItem] = []
        for i in startIndex..<endIndex {
            let asset = assets.object(at: i)
            newPhotos.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }
        
        photos.append(contentsOf: newPhotos)
        currentPage += 1
        hasMorePhotos = endIndex < assets.count
        isLoading = false
        isLoadingMore = false
    }

    private func loadAlbums() {
        var newAlbums: [Album] = []

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            if count > 0 {
                newAlbums.append(Album(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Untitled",
                    count: count
                ))
            }
        }

        albums = newAlbums
    }

    private func uploadPhoto(_ photo: PhotoItem) async {
        guard photo.asset != nil else { return }
    }
}
