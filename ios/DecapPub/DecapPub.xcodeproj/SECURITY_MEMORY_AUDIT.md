# Security, Memory, and Code Quality Audit
**Date:** January 17, 2026  
**Status:** Issues Identified - Awaiting Fixes

## Project Context

This is a photo publishing app for iOS 26.0+ that:
- Loads photos from the user's photo library
- Displays them in a gallery view
- Shows photo details with metadata (EXIF, camera info, location)
- Publishes photos to a Decap CMS backend via GitHub

The app uses Swift Concurrency (async/await), SwiftUI, and the Photos framework.

## Recent Work

1. Fixed metadata loading issues where metadata wasn't displaying in the info sheet
2. Removed spurious "up caret" button from detail view toolbar
3. Fixed "Done" button appearing doubled in metadata sheet
4. Simplified metadata loading to use `.task` modifier in MetadataView

## Current State

The app builds and runs. Metadata now loads correctly when tapping the info button in photo detail view.

---

## AUDIT FINDINGS

### CRITICAL ISSUES

#### Issue #12: Unbounded Image Cache (CRITICAL)
**File:** PhotoGalleryViewModel.swift, lines 85-87  
**Problem:**
```swift
private var imageCache: [String: UIImage] = [:]
```
- Dictionary-based cache with no size limit
- Stores both thumbnails AND full images (with "_full" suffix)
- No eviction policy
- No memory pressure handling
- Full images can be 10-50MB each
- Loading 100 photos could consume 5GB of memory

**Risk:** App will eventually crash with memory warnings on devices with limited RAM

**Fix Needed:** Replace with NSCache which has automatic eviction

---

### HIGH PRIORITY ISSUES

#### Issue #2: Full Image Retention (HIGH)
**File:** PhotoDetailView.swift, line 18, 88-91  
**Problem:**
- `@State private var fullImage: UIImage?` holds full-resolution image
- Only cleared in `onDisappear`
- If view stays in memory (NavigationStack keeps views alive), image persists
- Multiple navigations = multiple images retained

**Risk:** Memory accumulation if user browses multiple photos

**Fix Needed:** Use task cancellation and image manager properly

#### Issue #3: Cache Size Unbounded (HIGH)
**File:** PhotoGalleryViewModel.swift  
**Related to:** Issue #12  
**Problem:** No maximum cache size configured

**Fix Needed:** Implement cache size limits (e.g., 50MB thumbnails, 200MB total)

#### Issue #16: No Cache Invalidation (HIGH)
**File:** PhotoGalleryViewModel.swift  
**Problem:**
- Images cached forever
- No way to clear cache
- No memory warning observers
- No didReceiveMemoryWarning handling

**Fix Needed:** Add memory pressure handling

---

### MEDIUM PRIORITY ISSUES

#### Issue #7: Continuation Without Cancellation (MEDIUM)
**Files:** PhotoDetailView.swift, PhotoGalleryViewModel.swift, PublishView.swift  
**Locations:** Multiple `withCheckedContinuation` calls  
**Problem:**
- PHImageManager requests made with continuations
- If view dismissed during load, continuation resumes but view is gone
- No way to cancel PHImageManager requests
- Wasted CPU/network if downloading from iCloud

**Example:**
```swift
return await withCheckedContinuation { continuation in
    imageManager.requestImage(...) { image, _ in
        continuation.resume(returning: image)
    }
}
// No request cancellation when Task is cancelled
```

**Fix Needed:** 
- Track request IDs
- Cancel requests in task cancellation handler
- Use `withTaskCancellationHandler`

#### Issue #8: Race Condition in Image Loading (MEDIUM)
**File:** PhotoDetailView.swift, lines 84-87  
**Problem:**
```swift
guard fullImage == nil, !isLoadingImage else { return }
isLoadingImage = true
Task {
    fullImage = await viewModel.loadFullImage(for: photo)
    isLoadingImage = false
}
```
- Check and set are not atomic
- Rapid calls could start duplicate loads

**Risk:** Low in practice due to UI constraints, but technically incorrect

**Fix Needed:** Use actor or proper synchronization

---

### LOW PRIORITY ISSUES

#### Issue #1, #11, #17: Duplicate Imports (LOW)
**Files:** PhotoDetailView.swift (lines 1-3), PhotoGalleryViewModel.swift (lines 1-2), PublishView.swift (lines 1, 3)  
**Problem:** `import SwiftUI` appears twice in multiple files

**Fix:** Remove duplicates

#### Issue #6: Unsafe Key-Value Coding (LOW)
**File:** PhotoGalleryViewModel.swift, line 158  
**Problem:**
```swift
if let fileSize = resource.value(forKey: "fileSize") as? Int64
```
- Uses KVC on private API
- Not officially documented
- Could break in future iOS versions

**Risk:** Low - commonly used pattern in community

**Note:** This is a known limitation of PHAssetResource API

#### Issue #4, #18: Weak Self Usage (LOW)
**Files:** PhotoDetailView.swift line 89-91, PublishView.swift line 350-360  
**Problem:**
- Some Tasks capture self strongly
- Could prevent deallocation in edge cases

**Fix Needed:** Use `[weak self]` or ensure proper task cancellation

#### Issue #5: Dead Code (LOW)
**File:** PhotoDetailView.swift, line 43  
**Problem:** `DetailToolbar` accepts `onExpandSearch` parameter but button was removed

**Fix:** Remove parameter from struct

#### Issue #10: Temporary Debug Code (LOW)
**File:** PhotoDetailView.swift, line 289  
**Problem:**
```swift
.background(.red) // TEMPORARY - to see if it's rendering
```

**Fix:** Remove or change to proper color

#### Issue #14: Print Statements (LOW)
**Files:** PhotoGalleryViewModel.swift (lines 119, 120, 270)  
**Problem:** Console logging in production code

**Fix:** Remove or replace with proper logging framework

#### Issue #15: Mixed Concurrency Patterns (LOW)
**File:** PhotoGalleryViewModel.swift, line 277-283  
**Problem:**
```swift
DispatchQueue.main.async {
    completion(newStatus == .authorized || newStatus == .limited)
}
```
- Uses GCD instead of `@MainActor`
- Mixed with async/await elsewhere

**Fix:** Standardize on Swift Concurrency

#### Issue #9: No Error Handling (LOW)
**File:** PhotoGalleryViewModel.swift, loadMetadata function  
**Problem:**
- Silent failures when fullSizeImageURL is nil
- Silent failures when image properties can't be read
- User gets "No Metadata Available" with no explanation

**Fix:** Add error messages or logging for debugging

#### Issue #19, #20: Missing Cancellation (LOW)
**File:** PublishView.swift, AsyncThumbnailView  
**Problem:** PHImageManager requests not cancelled when view disappears

**Risk:** Very low - thumbnails are small

---

## RECOMMENDED FIX PRIORITY

### Phase 1: Critical Memory Issues
1. Replace Dictionary cache with NSCache (Issue #12)
2. Add cache size limits (Issue #3)
3. Implement memory warning handling (Issue #16)

### Phase 2: Image Lifecycle
4. Fix full image retention in PhotoDetailView (Issue #2)
5. Add proper task cancellation for image requests (Issue #7)

### Phase 3: Code Quality
6. Remove duplicate imports (Issues #1, #11, #17)
7. Remove debug code and print statements (Issues #10, #14)
8. Clean up dead code (Issue #5)

### Phase 4: Nice to Have
9. Standardize concurrency patterns (Issue #15)
10. Add proper error handling (Issue #9)
11. Fix race conditions (Issue #8)
12. Add weak self where appropriate (Issues #4, #18)

---

## IMPLEMENTATION NOTES

### NSCache Implementation Pattern

Replace this:
```swift
private var imageCache: [String: UIImage] = [:]
```

With this:
```swift
private let imageCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.totalCostLimit = 50 * 1024 * 1024 // 50MB for thumbnails
    cache.countLimit = 100 // Max 100 images
    return cache
}()

private let fullImageCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.totalCostLimit = 200 * 1024 * 1024 // 200MB for full images
    cache.countLimit = 10 // Max 10 full images
    return cache
}()
```

### Memory Warning Handling

Add to PhotoGalleryViewModel:
```swift
init() {
    loadAlbums()
    
    // Handle memory warnings
    NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.clearImageCache()
    }
}

private func clearImageCache() {
    imageCache.removeAllObjects()
    fullImageCache.removeAllObjects()
}
```

### Task Cancellation Pattern

Replace continuation pattern:
```swift
return await withCheckedContinuation { continuation in
    imageManager.requestImage(...) { image, _ in
        continuation.resume(returning: image)
    }
}
```

With cancellable pattern:
```swift
return await withTaskCancellationHandler {
    await withCheckedContinuation { continuation in
        let requestID = imageManager.requestImage(...) { image, _ in
            continuation.resume(returning: image)
        }
        // Store requestID for cancellation
    }
} onCancel: {
    // Cancel the image request
    imageManager.cancelImageRequest(requestID)
}
```

---

## USER PREFERENCES

- NO EMOJI in code, comments, or documentation
- User is frustrated with instability (Xcode crashes, metadata not working)
- User wants thorough reviews before making changes
- Direct, professional communication preferred

---

## NEXT STEPS

When resuming work:
1. Confirm which issues to fix
2. Implement fixes one phase at a time
3. Test after each phase
4. Do not make changes without explicit approval

---

**Document End**
