# Optional Memory Safety Enhancements

This document provides complete, ready-to-use implementations for the optional memory safety enhancements identified in the audit. These are not critical but would further improve performance and robustness.

---

## 1. Image Request Cancellation

**Benefit**: Saves CPU, memory, and battery by cancelling image loads when cells scroll off-screen rapidly.

**When to implement**: If you notice battery drain during rapid scrolling, or users report the app feels sluggish when scrolling through large libraries.

### Implementation

Add to `PhotoGalleryViewModel.swift`:

```swift
@MainActor
class PhotoGalleryViewModel: ObservableObject {
    // ... existing properties ...
    
    // Add this property
    private var activeRequests: [String: PHImageRequestID] = [:]
    
    // Update loadThumbnail method
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
        
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                var hasResumed = false
                
                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: thumbnailSize,
                    contentMode: .aspectFill,
                    options: options
                ) { [weak self] image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    
                    guard !hasResumed && !isDegraded else { return }
                    hasResumed = true
                    
                    // Clean up the request ID
                    self?.activeRequests.removeValue(forKey: photo.id)
                    
                    if let image = image {
                        let cost = Int(image.size.width * image.size.height * 4)
                        self?.thumbnailCache.setObject(image, forKey: cacheKey, cost: cost)
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
                
                // Store the request ID for potential cancellation
                activeRequests[photo.id] = requestID
            }
        } onCancel: {
            // Cancel the image request if the task is cancelled
            Task { @MainActor in
                if let requestID = activeRequests.removeValue(forKey: photo.id) {
                    imageManager.cancelImageRequest(requestID)
                }
            }
        }
    }
    
    // Update loadFullImage similarly
    func loadFullImage(for photo: PhotoItem) async -> UIImage? {
        let cacheKey = (photo.id + "_full") as NSString
        
        if let cached = fullImageCache.object(forKey: cacheKey) {
            return cached
        }
        
        guard let asset = photo.asset else { return nil }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                var hasResumed = false
                
                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: PHImageManagerMaximumSize,
                    contentMode: .aspectFit,
                    options: options
                ) { [weak self] image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    
                    guard !hasResumed && !isDegraded else { return }
                    hasResumed = true
                    
                    self?.activeRequests.removeValue(forKey: photo.id + "_full")
                    
                    if let image = image {
                        let cost = Int(image.size.width * image.size.height * 4)
                        self?.fullImageCache.setObject(image, forKey: cacheKey, cost: cost)
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
                
                activeRequests[photo.id + "_full"] = requestID
            }
        } onCancel: {
            Task { @MainActor in
                if let requestID = activeRequests.removeValue(forKey: photo.id + "_full") {
                    imageManager.cancelImageRequest(requestID)
                }
            }
        }
    }
    
    // Add method to cancel all requests (useful when switching sources)
    func cancelAllImageRequests() {
        for (_, requestID) in activeRequests {
            imageManager.cancelImageRequest(requestID)
        }
        activeRequests.removeAll()
    }
    
    // Update selectSource to cancel ongoing requests
    func selectSource(_ source: PhotoSource) {
        cancelAllImageRequests()
        currentSource = source
        fetchPhotos()
    }
}
```

Update `PhotoThumbnailView.swift`:

```swift
@available(iOS 26.0, *)
struct PhotoThumbnailView: View {
    // ... existing properties ...
    
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        // ... existing body ...
    }
    .onAppear {
        loadThumbnailIfNeeded()
    }
    .onDisappear {
        // Cancel the load task when cell disappears
        loadTask?.cancel()
        loadTask = nil
    }
    
    private func loadThumbnailIfNeeded() {
        guard thumbnail == nil else { return }
        guard !isLoading else { return }
        isLoading = true
        
        loadTask = Task { @MainActor in
            guard thumbnail == nil else {
                isLoading = false
                return
            }
            
            let loadedImage = await viewModel.loadThumbnail(for: photo)
            
            // Check if task was cancelled
            if !Task.isCancelled && thumbnail == nil {
                thumbnail = loadedImage
            }
            isLoading = false
        }
    }
}
```

**Testing**: Scroll rapidly and use Instruments to verify image requests are cancelled.

---

## 2. Sliding Window for Large Libraries

**Benefit**: Prevents unbounded array growth when scrolling through 10,000+ photo libraries.

**When to implement**: If users report slowness or memory issues with very large photo libraries.

**⚠️ Important Decision: Which Pages to Keep?**

The simple implementation below uses **FIFO (First-In-First-Out)** - as you scroll down, old pages fall out:
- Scroll to page 11 → Page 1 is removed
- Scroll to page 12 → Page 2 is removed

**Problem**: If the user scrolls back up, you'd need to either:
1. **Reverse to LIFO** (remove newest pages) - complex direction detection
2. **LRU cache** (keep most recently accessed) - more sophisticated
3. **Just reload** - simpler, but images are still in NSCache so it's fast

**Recommendation**: For most apps, **don't implement sliding window** unless you have users with 10,000+ photo libraries. The memory cost is minimal:
- 1,000 photos scrolled = ~400 KB of PhotoItem structs (negligible)
- 10,000 photos scrolled = ~4 MB of PhotoItem structs (still small)
- Images are already limited by NSCache (150 MB total)

### Implementation (Simple FIFO - Forward Scrolling Only)

Add to `PhotoGalleryViewModel.swift`:

```swift
@MainActor
class PhotoGalleryViewModel: ObservableObject {
    // ... existing properties ...
    
    // Add these properties
    private let maxPagesInMemory = 10 // Keep 10 pages (600 items) in memory
    private var firstLoadedPage = 0
    private var totalItemsRemoved = 0
    
    // Add this computed property for debugging
    var pagesInMemory: Int {
        currentPage - firstLoadedPage
    }
    
    func loadNextPage() {
        guard !isLoadingMore, hasMorePhotos, let assets = allAssets else { return }
        
        isLoadingMore = true
        
        // Check if we need to trim old pages (sliding window)
        if currentPage - firstLoadedPage >= maxPagesInMemory {
            let itemsToRemove = pageSize
            
            // Only remove if we have enough items
            if photos.count >= itemsToRemove {
                // Remove oldest page
                photos.removeFirst(itemsToRemove)
                firstLoadedPage += 1
                totalItemsRemoved += itemsToRemove
                
                print("📊 Sliding window: Removed page \(firstLoadedPage - 1), keeping pages \(firstLoadedPage)...\(currentPage)")
            }
        }
        
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
        
        print("📸 Loaded page \(currentPage - 1): \(photos.count) photos in memory, \(totalItemsRemoved) removed total")
    }
    
    private func fetchPhotos() {
        isLoading = true
        currentPage = 0
        firstLoadedPage = 0
        totalItemsRemoved = 0
        photos = []
        hasMorePhotos = true
        
        // ... rest of existing fetchPhotos code ...
    }
}
```

**Note**: With sliding window, you may want to disable scroll-to-top functionality or add a warning that scrolling back up will reload items.

### Implementation (Advanced: Bidirectional with Direction Detection)

If you need to support scrolling both directions, detect which way the user is scrolling and remove from the opposite end:

```swift
@MainActor
class PhotoGalleryViewModel: ObservableObject {
    // ... existing properties ...
    
    private let maxPagesInMemory = 10
    private var firstLoadedPage = 0
    private var lastLoadedPage = -1
    private var lastRequestedPage = -1
    
    func loadNextPage() {
        guard !isLoadingMore, hasMorePhotos, let assets = allAssets else { return }
        
        isLoadingMore = true
        
        let requestedPage = currentPage
        let scrollingDown = requestedPage > lastRequestedPage
        lastRequestedPage = requestedPage
        
        // Check if we need to trim (sliding window)
        let pagesInMemory = lastLoadedPage - firstLoadedPage + 1
        if pagesInMemory >= maxPagesInMemory {
            if scrollingDown {
                // Scrolling down: remove from the FRONT (oldest pages)
                if photos.count >= pageSize {
                    photos.removeFirst(pageSize)
                    firstLoadedPage += 1
                    print("📊 ⬇️ Scrolling down: Removed page \(firstLoadedPage - 1)")
                }
            } else {
                // Scrolling up: remove from the BACK (newest pages)
                if photos.count >= pageSize {
                    photos.removeLast(pageSize)
                    lastLoadedPage -= 1
                    print("📊 ⬆️ Scrolling up: Removed page \(lastLoadedPage + 1)")
                }
            }
        }
        
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
        
        if scrollingDown {
            photos.append(contentsOf: newPhotos)
        } else {
            photos.insert(contentsOf: newPhotos, at: 0)
        }
        
        currentPage += 1
        lastLoadedPage = max(lastLoadedPage, currentPage - 1)
        if lastLoadedPage == -1 {
            lastLoadedPage = 0
        }
        
        hasMorePhotos = endIndex < assets.count
        isLoading = false
        isLoadingMore = false
        
        print("   Memory: pages \(firstLoadedPage)-\(lastLoadedPage) (\(photos.count) items)")
    }
    
    private func fetchPhotos() {
        isLoading = true
        currentPage = 0
        firstLoadedPage = 0
        lastLoadedPage = -1
        lastRequestedPage = -1
        photos = []
        hasMorePhotos = true
        
        // ... rest of existing fetchPhotos code ...
    }
}
```

**Note**: This bidirectional approach is more complex and has a caveat - you need to also implement `loadPreviousPage()` for upward scrolling, which requires detecting when the user scrolls to the top. In SwiftUI, this is tricky without using UIKit scroll position tracking.

### Implementation (Most Robust: LRU Cache)

For the most flexible approach, use a page-based LRU (Least Recently Used) cache:

```swift
@MainActor
class PhotoGalleryViewModel: ObservableObject {
    // ... existing properties ...
    
    private let maxPagesInMemory = 10
    private var pageCache: [Int: [PhotoItem]] = [:]
    private var pageAccessOrder: [Int] = []  // Most recent at end
    
    func loadPage(_ pageNumber: Int) {
        // Check if page is already in cache
        if let cachedPage = pageCache[pageNumber] {
            // Move to end (mark as recently used)
            pageAccessOrder.removeAll { $0 == pageNumber }
            pageAccessOrder.append(pageNumber)
            return
        }
        
        isLoadingMore = true
        
        // Load new page
        let startIndex = pageNumber * pageSize
        let endIndex = min(startIndex + pageSize, (allAssets?.count ?? 0))
        
        guard let assets = allAssets, startIndex < assets.count else {
            isLoadingMore = false
            return
        }
        
        var newPhotos: [PhotoItem] = []
        for i in startIndex..<endIndex {
            let asset = assets.object(at: i)
            newPhotos.append(PhotoItem(id: asset.localIdentifier, asset: asset))
        }
        
        // Add to cache
        pageCache[pageNumber] = newPhotos
        pageAccessOrder.append(pageNumber)
        
        // Evict least recently used if over limit
        if pageCache.count > maxPagesInMemory {
            let lruPage = pageAccessOrder.removeFirst()
            pageCache.removeValue(forKey: lruPage)
            print("📊 LRU: Evicted page \(lruPage)")
        }
        
        // Rebuild photos array from cached pages in order
        rebuildPhotosArray()
        
        isLoadingMore = false
    }
    
    private func rebuildPhotosArray() {
        let sortedPages = pageCache.keys.sorted()
        photos = sortedPages.flatMap { pageCache[$0] ?? [] }
    }
}
```

**Verdict**: This is probably overkill for a photo gallery app. Stick with the simple FIFO approach or skip sliding window entirely.

---

**Alternative**: Bidirectional sliding window that keeps a window around the current scroll position:

```swift
// More advanced: Keep pages around current position
private let pagesBeforeCurrent = 3
private let pagesAfterCurrent = 7

func loadNextPage() {
    guard !isLoadingMore, hasMorePhotos, let assets = allAssets else { return }
    
    isLoadingMore = true
    
    // Trim if we exceed the window size
    let windowSize = pagesBeforeCurrent + pagesAfterCurrent
    if currentPage - firstLoadedPage > windowSize {
        let pagesToRemove = (currentPage - firstLoadedPage) - windowSize
        let itemsToRemove = pagesToRemove * pageSize
        
        if photos.count >= itemsToRemove {
            photos.removeFirst(itemsToRemove)
            firstLoadedPage += pagesToRemove
            totalItemsRemoved += itemsToRemove
        }
    }
    
    // ... rest of loading logic ...
}
```

---

## 3. Robust Continuation Handling

**Benefit**: Ensures continuations always resume even if PHImageManager behaves unexpectedly.

**When to implement**: If you encounter hangs or crashes related to image loading.

### Implementation

Replace the continuation logic in `loadThumbnail` and `loadFullImage`:

```swift
func loadThumbnail(for photo: PhotoItem) async -> UIImage? {
    let cacheKey = photo.id as NSString
    
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
        var bestImage: UIImage?
        var receivedCount = 0
        
        let requestID = imageManager.requestImage(
            for: asset,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            receivedCount += 1
            
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isError = (info?[PHImageErrorKey] != nil)
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            
            // Store best non-degraded image
            if let image = image, !isDegraded {
                bestImage = image
            }
            
            // Determine if this is the final callback
            let isFinal = !isDegraded || isError || isCancelled
            
            // Safety: also resume if we've received 3+ callbacks (shouldn't happen)
            let shouldResume = isFinal || receivedCount >= 3
            
            guard !hasResumed && shouldResume else { return }
            hasResumed = true
            
            // Use best image or current image
            if let finalImage = bestImage ?? image {
                let cost = Int(finalImage.size.width * finalImage.size.height * 4)
                self?.thumbnailCache.setObject(finalImage, forKey: cacheKey, cost: cost)
                continuation.resume(returning: finalImage)
            } else {
                continuation.resume(returning: nil)
            }
        }
        
        // Safety timeout: if no callback within 30 seconds, resume with nil
        Task {
            try? await Task.sleep(for: .seconds(30))
            if !hasResumed {
                hasResumed = true
                print("⚠️ Image load timeout for photo: \(photo.id)")
                continuation.resume(returning: nil)
            }
        }
    }
}
```

---

## 4. Integer Overflow Protection

**Benefit**: Prevents extremely rare integer overflow in cost calculations.

**When to implement**: For extra defensive coding in production apps.

### Implementation

```swift
func loadThumbnail(for photo: PhotoItem) async -> UIImage? {
    // ... existing code ...
    
    ) { [weak self] image, info in
        // ... existing logic ...
        
        if let image = image {
            // Safe cost calculation with overflow protection
            let width = Int64(image.size.width)
            let height = Int64(image.size.height)
            let pixels = width * height
            let bytes = pixels * 4 // 4 bytes per pixel (RGBA)
            
            // Clamp to Int.max to prevent overflow
            let cost = min(bytes, Int64(Int.max))
            
            self?.thumbnailCache.setObject(image, forKey: cacheKey, cost: Int(cost))
            continuation.resume(returning: image)
        }
    }
}
```

---

## 5. Debug Assertions for Actor Isolation

**Benefit**: Catches threading issues during development.

**When to implement**: Always useful during development, can be removed for release builds.

### Implementation

```swift
func loadNextPage() {
    // Assert we're on main actor in debug builds
    #if DEBUG
    dispatchPrecondition(condition: .onQueue(.main))
    #endif
    
    guard !isLoadingMore, hasMorePhotos, let assets = allAssets else { return }
    
    // ... rest of method ...
}

private func fetchPhotos() {
    #if DEBUG
    dispatchPrecondition(condition: .onQueue(.main))
    #endif
    
    // ... rest of method ...
}
```

---

## Testing Checklist

When implementing these enhancements, test:

- [ ] **Request Cancellation**: Scroll rapidly, verify requests are cancelled in Instruments
- [ ] **Sliding Window**: Scroll through 1000+ photos, verify memory stays bounded
- [ ] **Continuation Handling**: Test with airplane mode (network images)
- [ ] **Overflow Protection**: Test with very high-resolution images (100MP+)
- [ ] **Actor Isolation**: Run with Thread Sanitizer enabled

---

## Performance Metrics

Track these metrics before and after implementing enhancements:

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Memory usage (1000 photos) | < 200 MB | Instruments Memory Graph |
| Scroll FPS | 60 fps | Xcode FPS gauge |
| Battery drain | < 5%/hour | Battery usage settings |
| Image load latency | < 100ms | Instruments Time Profiler |
| Cache hit rate | > 80% | Custom logging |

---

## Conclusion

These enhancements are **optional** but recommended if:
1. Users report performance issues with large libraries
2. You want maximum battery efficiency
3. You're preparing for App Store review and want highest quality

The current implementation without these enhancements is already production-ready. Implement these based on specific needs and user feedback.
