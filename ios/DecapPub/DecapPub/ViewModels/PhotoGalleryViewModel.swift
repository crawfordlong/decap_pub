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
    @Published var currentSource: PhotoSource = .photoLibrary

    @AppStorage("siteName") var siteName = "Crawford Long"
    @AppStorage("siteEndpoint") private var siteEndpoint = "https://crawfordlong.com"
    @AppStorage("githubRepo") private var githubRepo = "crawfordlong/crawfordlong-com-2025"
    @AppStorage("githubBranch") private var githubBranch = "trunk"
    @AppStorage("contentPath") private var contentPath = "content/photos"
    @AppStorage("githubToken") private var githubToken = ""

    private let imageManager = PHCachingImageManager()
    private let thumbnailSize = CGSize(width: 200, height: 200)

    init() {
        loadAlbums()
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
        guard !githubToken.isEmpty else {
            // TODO: Show error - not authenticated
            return
        }

        for photo in photos {
            await uploadPhoto(photo)
        }
    }

    // MARK: - Private Methods

    private func requestPhotoLibraryAccess(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }
        default:
            completion(false)
        }
    }

    private func fetchPhotos() {
        isLoading = true

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 500

        let assets: PHFetchResult<PHAsset>

        switch currentSource {
        case .photoLibrary:
            assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        case .recents:
            if let recents = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil).firstObject {
                assets = PHAsset.fetchAssets(in: recents, options: fetchOptions)
            } else {
                assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            }
        case .favorites:
            fetchOptions.predicate = NSPredicate(format: "isFavorite == YES")
            assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        case .album(let albumId):
            let albumOptions = PHFetchOptions()
            albumOptions.predicate = NSPredicate(format: "localIdentifier == %@", albumId)
            if let album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: albumOptions).firstObject {
                assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
            } else {
                assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            }
        case .files:
            // File source handled separately
            isLoading = false
            return
        }

        var newPhotos: [PhotoItem] = []
        assets.enumerateObjects { asset, _, _ in
            var item = PhotoItem(id: asset.localIdentifier, asset: asset)
            newPhotos.append(item)
        }

        photos = newPhotos
        isLoading = false

        // Load thumbnails asynchronously
        loadThumbnails()
    }

    private func loadThumbnails() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        for (index, photo) in photos.enumerated() {
            guard let asset = photo.asset else { continue }

            imageManager.requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, _ in
                Task { @MainActor in
                    if let image = image, index < self?.photos.count ?? 0 {
                        self?.photos[index].thumbnail = image
                    }
                }
            }
        }
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
        guard let asset = photo.asset else { return }

        // Get full resolution image data
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = true

        // TODO: Call backend library to:
        // 1. Format content for Decap CMS (frontmatter + image)
        // 2. Create GitHub commit via API
        // 3. Handle upload progress/errors

        print("Would upload photo: \(photo.id) to \(githubRepo)")
    }
}
