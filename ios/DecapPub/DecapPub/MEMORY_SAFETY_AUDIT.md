# Memory Safety Audit - Gallery View

## Executive Summary

**Overall Assessment**: ✅ **GOOD** - The gallery implementation has strong memory safety practices with several areas for improvement.

**Critical Issues**: 1  
**High Priority**: 2  
**Medium Priority**: 3  
**Low Priority**: 2

---

## 🔴 CRITICAL ISSUES

### 1. Missing NotificationCenter Observer Cleanup
**Location**: `PhotoGalleryViewModel.init()` and `setupMemoryWarningHandler()`  
**Risk**: Memory leak - observer never gets removed  
**Impact**: Each view model instance adds an observer that persists even after the view model is deallocated

**Current Code**:
```swift
private func setupMemoryWarningHandler() {
    NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.handleMemoryWarning()
    }
}
```

**Issue**: While using `[weak self]` prevents a strong reference cycle, the observer itself is never removed from NotificationCenter, causing a leak.

**Fix Required**:
```swift
private var memoryWarningObserver: NSObjectProtocol?

deinit {
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
```

---

## 🟠 HIGH PRIORITY ISSUES

### 2. PHImageManager Request Not Cancellable
**Location**: `loadThumbnail()` and `loadFullImage()` methods  
**Risk**: Wasted resources loading images for views that have already disappeared  
**Impact**: Medium - can cause unnecessary CPU/memory usage and battery drain

**Current Code**:
```swift
imageManager.requestImage(
    for: asset,
    targetSize: thumbnailSize,
    contentMode: .aspectFill,
    options: options
) { [weak self] image, info in
    // ... continuation code
}
```

**Issue**: When cells scroll off-screen rapidly, the image requests continue to execute. With pagination loading 60 items, this can result in many unnecessary background operations.

**Recommended Fix**:
```swift
// Store request IDs to enable cancellation
private var activeRequests: [String: PHImageRequestID] = [:]

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
                
                self?.activeRequests.removeValue(forKey: photo.id)
                
                if let image = image {
                    let cost = Int(image.size.width * image.size.height * 4)
                    self?.thumbnailCache.setObject(image, forKey: cacheKey, cost: cost)
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            activeRequests[photo.id] = requestID
        }
    } onCancel: {
        if let requestID = activeRequests.removeValue(forKey: photo.id) {
            imageManager.cancelImageRequest(requestID)
        }
    }
}

// Add cleanup method
func cancelAllImageRequests() {
    for (_, requestID) in activeRequests {
        imageManager.cancelImageRequest(requestID)
    }
    activeRequests.removeAll()
}
```

### 3. Potential Array Mutation During Enumeration
**Location**: `GalleryView.body` - `sendSelectedPhotos()` and `publishSelectedPhotos()`  
**Risk**: Crash if view model photos array changes during filtering  
**Impact**: Low probability but catastrophic if it happens

**Current Code**:
```swift
private func sendSelectedPhotos() {
    let photosToSend = viewModel.photos.filter { selectedPhotos.contains($0.id) }
    Task {
        await viewModel.sendToSite(photos: photosToSend)
        // ... cleanup
    }
}
```

**Issue**: If `viewModel.photos` is mutated on another thread while filtering, this could crash. The view model is `@MainActor` which helps, but better to be explicit.

**Recommended Fix**:
```swift
private func sendSelectedPhotos() {
    // Capture the array snapshot
    let currentPhotos = viewModel.photos
    let photosToSend = currentPhotos.filter { selectedPhotos.contains($0.id) }
    Task {
        await viewModel.sendToSite(photos: photosToSend)
        await MainActor.run {
            withAnimation(.spring(response: 0.3)) {
                isSelecting = false
                selectedPhotos.removeAll()
            }
        }
    }
}
```

---

## 🟡 MEDIUM PRIORITY ISSUES

### 4. Unbounded Array Growth
**Location**: `PhotoGalleryViewModel.loadNextPage()`  
**Risk**: Memory growth proportional to scroll depth  
**Impact**: For users with 10,000+ photos, scrolling deep could allocate thousands of PhotoItem structs

**Current Code**:
```swift
photos.append(contentsOf: newPhotos)
```

**Issue**: The `photos` array grows indefinitely as the user scrolls. While PhotoItem only holds a reference to PHAsset (not the image data), having thousands in memory is still suboptimal.

**Mitigation Options**:
1. Implement a sliding window (keep only N pages in memory)
2. Add monitoring and warnings for very large arrays
3. Provide a "reset/reload" option for users

**Recommended Approach**:
```swift
// Add sliding window configuration
private let maxPagesInMemory = 10 // 600 items max
private var firstLoadedPage = 0

func loadNextPage() {
    guard !isLoadingMore, hasMorePhotos, let assets = allAssets else { return }
    
    isLoadingMore = true
    
    // Check if we need to trim old pages
    if currentPage - firstLoadedPage >= maxPagesInMemory {
        let itemsToRemove = pageSize
        photos.removeFirst(itemsToRemove)
        firstLoadedPage += 1
    }
    
    // ... rest of loading logic
}
```

### 5. Double Image Loading Risk
**Location**: `PhotoThumbnailView.loadThumbnailIfNeeded()`  
**Risk**: Race condition could load same image twice  
**Impact**: Wasted memory and processing

**Current Code**:
```swift
private func loadThumbnailIfNeeded() {
    guard thumbnail == nil, !isLoading else { return }
    
    isLoading = true
    Task {
        thumbnail = await viewModel.loadThumbnail(for: photo)
        isLoading = false
    }
}
```

**Issue**: Between checking `thumbnail == nil` and setting `isLoading = true`, the view could be recreated or rerendered, potentially starting a second load.

**Better Approach**:
```swift
private func loadThumbnailIfNeeded() {
    guard thumbnail == nil else { return }
    
    // Set loading immediately to prevent race
    guard !isLoading else { return }
    isLoading = true
    
    Task { @MainActor in
        // Check again after async boundary
        guard thumbnail == nil else {
            isLoading = false
            return
        }
        
        let loadedImage = await viewModel.loadThumbnail(for: photo)
        
        // Only update if still nil (view might have been reused)
        if thumbnail == nil {
            thumbnail = loadedImage
        }
        isLoading = false
    }
}
```

### 6. Continuation Resume Guard Insufficient
**Location**: `loadThumbnail()` and `loadFullImage()` methods  
**Risk**: Potential continuation not resumed if multiple degraded images arrive  
**Impact**: Task suspension indefinitely (very low probability)

**Current Code**:
```swift
) { [weak self] image, info in
    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
    
    guard !hasResumed && !isDegraded else { return }
    hasResumed = true
    // ... resume continuation
}
```

**Issue**: If PHImageManager only delivers degraded images and then fails, the continuation never resumes.

**Safer Approach**:
```swift
return await withCheckedContinuation { continuation in
    var hasResumed = false
    var bestImage: UIImage?
    
    let requestID = imageManager.requestImage(
        for: asset,
        targetSize: thumbnailSize,
        contentMode: .aspectFill,
        options: options
    ) { [weak self] image, info in
        let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
        let isError = (info?[PHImageErrorKey] != nil)
        let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
        
        // Store best image received so far
        if let image = image, !isDegraded {
            bestImage = image
        }
        
        // Resume on final result (success, error, or cancellation)
        let isFinal = !isDegraded || isError || isCancelled
        
        guard !hasResumed && isFinal else { return }
        hasResumed = true
        
        if let finalImage = bestImage ?? image {
            let cost = Int(finalImage.size.width * finalImage.size.height * 4)
            self?.thumbnailCache.setObject(finalImage, forKey: cacheKey, cost: cost)
            continuation.resume(returning: finalImage)
        } else {
            continuation.resume(returning: nil)
        }
    }
}
```

---

## 🟢 LOW PRIORITY ISSUES

### 7. NSCache Cost Calculation Could Overflow
**Location**: `loadThumbnail()` and `loadFullImage()` cost calculations  
**Risk**: Integer overflow for very large images  
**Impact**: Extremely low - would require images > 715,000 × 715,000 pixels

**Current Code**:
```swift
let cost = Int(image.size.width * image.size.height * 4)
```

**Safer Version**:
```swift
let pixels = Int64(image.size.width) * Int64(image.size.height)
let bytes = pixels * 4
let cost = min(bytes, Int64(Int.max))
```

### 8. Missing Scoped Actor Isolation
**Location**: Various locations in PhotoGalleryViewModel  
**Risk**: Potential race conditions if methods are called from different contexts  
**Impact**: Very low due to @MainActor on class, but could be more explicit

**Enhancement**:
```swift
func loadNextPage() {
    // Add explicit isolation check in critical sections
    dispatchPrecondition(condition: .onQueue(.main))
    
    guard !isLoadingMore, hasMorePhotos, let assets = allAssets else { return }
    // ... rest of method
}
```

---

## ✅ GOOD PRACTICES OBSERVED

1. **Weak Self Captures**: Properly uses `[weak self]` in closures to prevent retain cycles
2. **NSCache for Images**: Excellent use of NSCache with proper cost limits and count limits
3. **Memory Warning Handling**: Responds to memory warnings by clearing caches
4. **Lazy Loading**: Uses LazyVGrid to only render visible cells
5. **@MainActor Isolation**: View model is properly marked @MainActor
6. **Pagination**: Limits initial load to 60 items instead of loading entire library
7. **On-Demand Image Loading**: Images loaded only when needed, not stored in PhotoItem
8. **Smart Pre-loading**: Loads next page 10 items before the end
9. **Struct Value Types**: PhotoItem, PhotoMetadata, and Album are structs (no reference cycles)
10. **PHAsset References**: Stores PHAsset references instead of loading all image data upfront

---

## RECOMMENDATIONS SUMMARY

### Immediate Action Required
1. ✅ **Fix NotificationCenter observer cleanup** (Critical)

### High Priority Improvements
2. ✅ **Add image request cancellation** when cells scroll off-screen
3. ✅ **Add array snapshot captures** before filtering in selection methods

### Future Enhancements
4. Consider implementing sliding window for very large photo libraries
5. Strengthen continuation resume guarantees
6. Add explicit actor isolation preconditions in debug builds

---

## MEMORY USAGE ESTIMATES

With current implementation (assuming 1000 photos scrolled):

| Component | Per Item | 1000 Items |
|-----------|----------|------------|
| PhotoItem struct | ~40 bytes | ~40 KB |
| PHAsset reference | ~200 bytes | ~200 KB |
| Thumbnails (cached) | ~1 MB | Limited to 50 = ~50 MB |
| Full images (cached) | ~10 MB | Limited to 10 = ~100 MB |
| **Total** | - | **~150 MB** |

This is acceptable for a photo gallery app. The caches have proper limits and respond to memory warnings.

---

## TESTING RECOMMENDATIONS

1. **Stress Test**: Load app with 10,000+ photo library and scroll rapidly
2. **Memory Profiler**: Use Instruments to verify no leaks when pushing/popping view
3. **Simulate Memory Warning**: Trigger warnings and verify caches clear properly
4. **Task Cancellation**: Verify image loads cancel when scrolling rapidly
5. **Concurrent Access**: Test rapid source switching while scrolling

---

## FINAL VERDICT

The gallery view implementation demonstrates **solid memory safety practices** with efficient caching, proper weak references, and thoughtful pagination. The critical issue with NotificationCenter must be fixed, but otherwise this is production-ready code with room for optimization under extreme use cases.

**Grade: B+** (A- after fixing the observer cleanup issue)
