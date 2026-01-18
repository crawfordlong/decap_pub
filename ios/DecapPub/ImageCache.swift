import Foundation
import UIKit
import Photos

/// LRU (Least Recently Used) image cache with size limits
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    
    private var thumbnailCache: [String: CachedImage] = [:]
    private var fullImageCache: [String: CachedImage] = [:]
    private var accessOrder: [String] = []
    
    // Memory limits
    private let maxThumbnailCacheSize: Int = 20 * 1024 * 1024  // 20MB
    private let maxFullImageCacheSize: Int = 50 * 1024 * 1024  // 50MB
    
    private var currentThumbnailSize: Int = 0
    private var currentFullImageSize: Int = 0
    
    private struct CachedImage {
        let image: UIImage
        let size: Int
        var lastAccessed: Date
    }
    
    private init() {
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Thumbnail Cache
    
    func cacheThumbnail(_ image: UIImage, for key: String) {
        let size = estimateImageSize(image)
        
        // Remove if already cached (to update access time)
        if let existing = thumbnailCache[key] {
            currentThumbnailSize -= existing.size
        }
        
        thumbnailCache[key] = CachedImage(image: image, size: size, lastAccessed: Date())
        currentThumbnailSize += size
        updateAccessOrder(key)
        
        // Evict if over limit
        while currentThumbnailSize > maxThumbnailCacheSize && !thumbnailCache.isEmpty {
            evictLeastRecentlyUsedThumbnail()
        }
    }
    
    func thumbnail(for key: String) -> UIImage? {
        guard var cached = thumbnailCache[key] else {
            return nil
        }
        
        // Update access time
        cached.lastAccessed = Date()
        thumbnailCache[key] = cached
        updateAccessOrder(key)
        
        return cached.image
    }
    
    func removeThumbnail(for key: String) {
        if let cached = thumbnailCache.removeValue(forKey: key) {
            currentThumbnailSize -= cached.size
            accessOrder.removeAll { $0 == key }
        }
    }
    
    // MARK: - Full Image Cache
    
    func cacheFullImage(_ image: UIImage, for key: String) {
        let size = estimateImageSize(image)
        
        // Remove if already cached (to update access time)
        if let existing = fullImageCache[key] {
            currentFullImageSize -= existing.size
        }
        
        fullImageCache[key] = CachedImage(image: image, size: size, lastAccessed: Date())
        currentFullImageSize += size
        updateAccessOrder(key)
        
        // Evict if over limit
        while currentFullImageSize > maxFullImageCacheSize && !fullImageCache.isEmpty {
            evictLeastRecentlyUsedFullImage()
        }
    }
    
    func fullImage(for key: String) -> UIImage? {
        guard var cached = fullImageCache[key] else {
            return nil
        }
        
        // Update access time
        cached.lastAccessed = Date()
        fullImageCache[key] = cached
        updateAccessOrder(key)
        
        return cached.image
    }
    
    func removeFullImage(for key: String) {
        if let cached = fullImageCache.removeValue(forKey: key) {
            currentFullImageSize -= cached.size
            accessOrder.removeAll { $0 == key }
        }
    }
    
    // MARK: - Cache Management
    
    func clearAll() {
        thumbnailCache.removeAll()
        fullImageCache.removeAll()
        accessOrder.removeAll()
        currentThumbnailSize = 0
        currentFullImageSize = 0
    }
    
    func clearThumbnails() {
        thumbnailCache.removeAll()
        currentThumbnailSize = 0
    }
    
    func clearFullImages() {
        fullImageCache.removeAll()
        currentFullImageSize = 0
    }
    
    @objc private func handleMemoryWarning() {
        // Clear all full images on memory warning
        clearFullImages()
        
        // Reduce thumbnail cache by 50%
        let targetSize = maxThumbnailCacheSize / 2
        while currentThumbnailSize > targetSize && !thumbnailCache.isEmpty {
            evictLeastRecentlyUsedThumbnail()
        }
    }
    
    // MARK: - Private Methods
    
    private func updateAccessOrder(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
    
    private func evictLeastRecentlyUsedThumbnail() {
        // Find the least recently used item
        var oldestKey: String?
        var oldestDate: Date = Date()
        
        for (key, cached) in thumbnailCache {
            if cached.lastAccessed < oldestDate {
                oldestDate = cached.lastAccessed
                oldestKey = key
            }
        }
        
        if let key = oldestKey {
            removeThumbnail(for: key)
        }
    }
    
    private func evictLeastRecentlyUsedFullImage() {
        // Find the least recently used item
        var oldestKey: String?
        var oldestDate: Date = Date()
        
        for (key, cached) in fullImageCache {
            if cached.lastAccessed < oldestDate {
                oldestDate = cached.lastAccessed
                oldestKey = key
            }
        }
        
        if let key = oldestKey {
            removeFullImage(for: key)
        }
    }
    
    private func estimateImageSize(_ image: UIImage) -> Int {
        // Estimate memory size: width * height * 4 bytes per pixel (RGBA)
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return width * height * 4
    }
    
    // MARK: - Cache Stats
    
    var stats: String {
        let thumbnailMB = Double(currentThumbnailSize) / (1024 * 1024)
        let fullImageMB = Double(currentFullImageSize) / (1024 * 1024)
        let thumbnailCount = thumbnailCache.count
        let fullImageCount = fullImageCache.count
        
        return """
        Thumbnail Cache: \(thumbnailCount) images, \(String(format: "%.1f", thumbnailMB)) MB
        Full Image Cache: \(fullImageCount) images, \(String(format: "%.1f", fullImageMB)) MB
        """
    }
}
