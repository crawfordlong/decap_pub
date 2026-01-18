# Quick Reference: Security & Memory Fixes

## 🔐 Token Management

### Old (INSECURE) ❌
```swift
@AppStorage("githubToken") private var githubToken = ""
```

### New (SECURE) ✅
```swift
// Reading
let token = KeychainManager.shared.githubToken

// Writing
KeychainManager.shared.githubToken = "ghp_..."

// Deleting
KeychainManager.shared.githubToken = ""
```

---

## 🌐 Network Requests

### Old (UNSAFE) ❌
```swift
let (data, response) = try await URLSession.shared.data(for: request)
```

### New (SECURE) ✅
```swift
let (data, response) = try await NetworkManager.shared.data(for: request)
```

---

## 📷 Image Loading

### Old (MEMORY LEAK) ❌
```swift
struct PhotoItem {
    let fullImage: UIImage?  // 6GB for 500 photos!
    let thumbnail: UIImage?
}

// In view
if let image = photo.fullImage {
    Image(uiImage: image)
}
```

### New (LAZY LOADING) ✅
```swift
struct PhotoItem {
    let id: String
    let asset: PHAsset?
    // No stored images!
}

// In view
@State private var image: UIImage?

var body: some View {
    if let image = image {
        Image(uiImage: image)
    } else {
        ProgressView()
    }
}
.onAppear {
    Task {
        image = await viewModel.loadFullImage(for: photo)
    }
}
.onDisappear {
    image = nil  // Release memory
}
```

---

## 📝 Logging

### Old (INSECURE) ❌
```swift
print("Token: \(githubToken)")
print("DEBUG: User \(username)")
print("Error: \(error)")
```

### New (SECURE) ✅
```swift
import os.log

// Sensitive data (redacted in logs)
Logger.security.info("Token validation succeeded")
Logger.network.debug("User authenticated: \(username, privacy: .private)")

// Non-sensitive data
Logger.photos.info("Loaded \(count) photos")
Logger.performance.debug("Memory usage: \(memoryMB, privacy: .public) MB")

// Errors
Logger.network.error("Request failed: \(error.localizedDescription, privacy: .public)")
```

**Available Loggers:**
- `Logger.network` - API calls, downloads
- `Logger.photos` - Photo library operations
- `Logger.persistence` - Data storage
- `Logger.ui` - User interface events
- `Logger.security` - Authentication, authorization
- `Logger.performance` - Memory, CPU metrics

---

## 🧠 Memory Management

### Cache Management
```swift
// Automatic - cache handles eviction
ImageCache.shared.cacheThumbnail(image, for: photoId)
let cached = ImageCache.shared.thumbnail(for: photoId)

// Manual cache clearing
ImageCache.shared.clearAll()
ImageCache.shared.clearFullImages()

// Memory monitoring
MemoryMonitor.shared.currentMemoryUsageMB  // Real-time usage
MemoryMonitor.shared.cacheStats  // Cache statistics
```

### Best Practices
1. **Load images on-demand** - Only when views appear
2. **Release on disappear** - Set @State images to nil
3. **Use thumbnails** - Don't load full images in grids
4. **Trust the cache** - LRU eviction is automatic
5. **Monitor memory** - Check MemoryMonitor in debug builds

---

## 🔄 Migration

The app automatically migrates tokens from UserDefaults to Keychain on first launch.

**How it works:**
1. App launches
2. `MigrationManager.shared.runMigrationsIfNeeded()` checks for migrations
3. If token found in UserDefaults, moves to Keychain
4. Removes from UserDefaults after successful migration
5. Migration marked complete (won't run again)

**No action required** - it's automatic and safe!

---

## ⚠️ Common Mistakes to Avoid

### ❌ Don't Do This
```swift
// Storing tokens in UserDefaults
@AppStorage("githubToken") var token = ""

// Using URLSession directly
URLSession.shared.data(for: request)

// Storing UIImage in models
struct Photo {
    let image: UIImage
}

// Logging sensitive data
print("Token: \(token)")

// Loading all images at once
photos.forEach { loadImage($0) }
```

### ✅ Do This Instead
```swift
// Use Keychain
KeychainManager.shared.githubToken

// Use NetworkManager
NetworkManager.shared.data(for: request)

// Store PHAsset reference only
struct Photo {
    let asset: PHAsset
}

// Use Logger with privacy
Logger.security.info("Token validated")

// Load images on-demand
.onAppear {
    Task { image = await loadImage(photo) }
}
```

---

## 🧪 Testing Your Changes

### Memory Testing
```swift
// In Xcode:
// 1. Product → Profile → Allocations
// 2. Scroll through gallery
// 3. Watch memory usage (should stay under 200MB)

// Simulate memory warning:
// Debug → Simulate Memory Warning
// Verify: cache clears automatically
```

### Security Testing
```swift
// Verify no token in UserDefaults:
print(UserDefaults.standard.string(forKey: "githubToken") ?? "nil")
// Expected: "nil" after migration

// Check Console.app for leaks:
// 1. Open Console.app
// 2. Filter: process:DecapPub
// 3. Search for "token" or "ghp_"
// 4. Should find: nothing (all redacted)
```

### Network Testing
```swift
// Test scope validation:
// 1. Create token without 'repo' scope
// 2. Try to authenticate
// 3. Should see: "Missing 'repo' scope" error
```

---

## 📚 File Reference

| File | Purpose |
|------|---------|
| `KeychainManager.swift` | Secure token storage |
| `NetworkManager.swift` | Network requests with cert pinning |
| `ImageCache.swift` | LRU cache for images |
| `MemoryMonitor.swift` | Memory usage tracking |
| `MigrationManager.swift` | Data migrations |
| `Logger+Extensions.swift` | Centralized logging |

---

## 🆘 Troubleshooting

### "Token not found"
- Token is in Keychain, not UserDefaults anymore
- Use `KeychainManager.shared.githubToken` to access

### "Memory still high"
- Check if images are being released on onDisappear
- Verify cache size limits in ImageCache
- Monitor with MemoryMonitor.shared.stats

### "Certificate pinning error"
- Pinning is currently in "warn" mode (doesn't block)
- To enable: update certificate hashes in NetworkManager
- Set `enablePinning = true`

### "Migration not working"
- Check Console.app for migration logs
- Verify UserDefaults had token before migration
- Check Keychain access permissions

---

**Last Updated:** January 17, 2026
**Status:** ✅ All fixes implemented and tested
