import Foundation
import Photos
import UIKit
import SwiftUI
import os.log

@MainActor
class PublishManager: ObservableObject {
    @AppStorage("githubRepo") private var githubRepo = "crawfordlong/crawfordlong-com-2025"
    @AppStorage("githubBranch") private var githubBranch = "trunk"
    @AppStorage("contentPath") private var contentPath = "content/photos"
    
    private let apiBase = "https://api.github.com"
    
    private var githubToken: String {
        KeychainManager.shared.githubToken
    }
    
    @Published var cmsConfig: DecapCMSConfig?
    @Published var configLoadError: String?
    
    enum PublishError: LocalizedError {
        case notAuthenticated
        case invalidResponse
        case networkError(String)
        case gitHubError(String)
        case configError(String)
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not authenticated. Please sign in with GitHub."
            case .invalidResponse:
                return "Invalid response from GitHub"
            case .networkError(let message):
                return "Network error: \(message)"
            case .gitHubError(let message):
                return "GitHub error: \(message)"
            case .configError(let message):
                return "Configuration error: \(message)"
            }
        }
    }
    
    struct DecapCMSConfig {
        let mediaFolder: String
        let publicFolder: String
        let photoCollection: CollectionConfig?
        let notesCollection: CollectionConfig?
        
        struct CollectionConfig {
            let name: String
            let folder: String
            let path: String?           // Path template with variables
            let mediaFolder: String     // Can be empty string for leaf bundles
            let publicFolder: String    // Can be empty string for relative refs
            let fields: [Field]
            let slugTemplate: String?
            
            var isLeafBundle: Bool {
                // If path ends with /index, it's a leaf bundle
                return path?.hasSuffix("/index") ?? false
            }
            
            var usesMediaInEntry: Bool {
                // Empty media_folder means store with entry
                return mediaFolder.isEmpty
            }
            
            struct Field {
                let name: String
                let label: String
                let widget: String
                let required: Bool
                let defaultValue: String?
            }
        }
    }
    
    // MARK: - Configuration
    
    func loadCMSConfig() async {
        do {
            let configPath = "static/admin/config.yml"
            let configContent = try await fetchFileFromGitHub(path: configPath)
            
            guard !configContent.isEmpty else {
                configLoadError = "config.yml not found at \(configPath)"
                return
            }
            
            cmsConfig = parseDecapConfig(configContent)
            configLoadError = nil
            Logger.persistence.info("Loaded CMS config successfully")
        } catch {
            configLoadError = "Failed to load config: \(error.localizedDescription)"
            Logger.persistence.error("Failed to load CMS config: \(error.localizedDescription)")
        }
    }
    
    private func parseDecapConfig(_ yaml: String) -> DecapCMSConfig {
        let lines = yaml.components(separatedBy: .newlines)
        
        var mediaFolder = "static/images"
        var publicFolder = "/images"
        var photoCollection: DecapCMSConfig.CollectionConfig?
        var notesCollection: DecapCMSConfig.CollectionConfig?
        
        _ = 0  // currentIndent placeholder
        var inCollections = false
        var inPhotoCollection = false
        var inNotesCollection = false
        var photoCollectionStartLine = 0
        var notesCollectionStartLine = 0
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Top-level config
            if line.hasPrefix("media_folder:") {
                mediaFolder = extractValue(from: line)
            }
            if line.hasPrefix("public_folder:") {
                publicFolder = extractValue(from: line)
            }
            
            // Collections section
            if line.hasPrefix("collections:") {
                inCollections = true
                continue
            }
            
            // Look for photo collection
            if inCollections && (trimmed.contains("name: photos") || trimmed.contains("name: photo") || trimmed.contains("name: 'photos'") || trimmed.contains("name: \"photos\"")) {
                inPhotoCollection = true
                photoCollectionStartLine = index
            }
            
            // Look for notes collection
            if inCollections && (trimmed.contains("name: notes") || trimmed.contains("name: note") || trimmed.contains("name: 'notes'") || trimmed.contains("name: \"notes\"")) {
                inNotesCollection = true
                notesCollectionStartLine = index
            }
            
            // If we found the photo collection, parse it
            if inPhotoCollection && index > photoCollectionStartLine {
                // Stop if we hit another collection
                if trimmed.hasPrefix("- name:") {
                    inPhotoCollection = false
                }
            }
            
            // If we found the notes collection, parse it
            if inNotesCollection && index > notesCollectionStartLine {
                // Stop if we hit another collection
                if trimmed.hasPrefix("- name:") {
                    inNotesCollection = false
                }
            }
        }
        
        // Parse the collections if found
        if photoCollectionStartLine > 0 {
            photoCollection = parseCollection(from: lines, startingAt: photoCollectionStartLine, name: "photos")
        }
        if notesCollectionStartLine > 0 {
            notesCollection = parseCollection(from: lines, startingAt: notesCollectionStartLine, name: "notes")
        }
        
        return DecapCMSConfig(
            mediaFolder: mediaFolder,
            publicFolder: publicFolder,
            photoCollection: photoCollection,
            notesCollection: notesCollection
        )
    }
    
    private func parseCollection(from lines: [String], startingAt: Int, name: String) -> DecapCMSConfig.CollectionConfig {
        var folder = "content/\(name)"
        var path: String?
        var mediaFolder = ""
        var publicFolder = ""
        var slugTemplate: String?
        
        for i in (startingAt + 1)..<min(startingAt + 100, lines.count) {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Stop if we hit another collection
            if trimmed.hasPrefix("- name:") && i != startingAt {
                break
            }
            
            if trimmed.hasPrefix("folder:") {
                folder = extractValue(from: line)
                Logger.persistence.debug("Found folder: \(folder)")
            }
            if trimmed.hasPrefix("path:") {
                path = extractValue(from: line)
                Logger.persistence.debug("Found path: \(path ?? "empty")")
            }
            if trimmed.hasPrefix("media_folder:") {
                mediaFolder = extractValue(from: line)
                Logger.persistence.debug("Found media_folder: '\(mediaFolder)'")
            }
            if trimmed.hasPrefix("public_folder:") {
                publicFolder = extractValue(from: line)
                Logger.persistence.debug("Found public_folder: '\(publicFolder)'")
            }
            if trimmed.hasPrefix("slug:") {
                slugTemplate = extractValue(from: line)
                Logger.persistence.debug("Found slug: \(slugTemplate ?? "empty")")
            }
        }
        
        Logger.persistence.debug("Parsed collection '\(name)':")
        Logger.persistence.debug("  - folder: \(folder)")
        Logger.persistence.debug("  - path: \(path ?? "nil")")
        Logger.persistence.debug("  - mediaFolder: '\(mediaFolder)'")
        Logger.persistence.debug("  - publicFolder: '\(publicFolder)'")
        Logger.persistence.debug("  - slugTemplate: \(slugTemplate ?? "nil")")
        
        return DecapCMSConfig.CollectionConfig(
            name: name,
            folder: folder,
            path: path,
            mediaFolder: mediaFolder,
            publicFolder: publicFolder,
            fields: [],
            slugTemplate: slugTemplate
        )
    }
    
    private func extractValue(from line: String) -> String {
        let parts = line.components(separatedBy: ":")
        guard parts.count > 1 else { return "" }
        
        var value = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
        
        // Remove inline comments (but only if outside of quotes)
        // First check if there are quotes
        let hasQuotes = value.hasPrefix("\"") || value.hasPrefix("'")
        if hasQuotes {
            // Find the closing quote
            let quoteChar = value.first!
            if let secondQuoteIndex = value.dropFirst().firstIndex(of: quoteChar) {
                // Extract only the quoted content and what's before the comment
                let endIndex = value.index(after: secondQuoteIndex)
                value = String(value[..<endIndex])
            }
        } else {
            // No quotes, so strip comment if present
            if let commentIndex = value.firstIndex(of: "#") {
                value = String(value[..<commentIndex]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Remove quotes if present (handle both single and double quotes)
        while (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            if value.count >= 2 {
                value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            } else {
                break
            }
        }
        
        return value
    }
    
    // MARK: - Tags Management
    
    func loadTags(for collection: String = "photos") async -> [String] {
        guard !githubToken.isEmpty else { return [] }
        
        let collectionPath = collection == "photos" ? contentPath : "content/\(collection)"
        
        do {
            let tagsPath = "\(collectionPath)/tags.json"
            let content = try await fetchFileFromGitHub(path: tagsPath)
            
            if let data = content.data(using: .utf8),
               let tags = try? JSONDecoder().decode([String].self, from: data) {
                return tags.sorted()
            }
        } catch {
            Logger.persistence.info("Tags file not found for \(collection), using defaults")
        }
        
        // Default tags based on collection
        if collection == "notes" {
            return ["personal", "work", "ideas", "projects", "reference"]
        } else {
            return ["photography", "travel", "nature", "portrait", "landscape", "street", "architecture"]
        }
    }
    
    func updateTagsFile(_ tags: [String], for collection: String = "photos") async throws {
        guard !githubToken.isEmpty else {
            throw PublishError.notAuthenticated
        }
        
        let collectionPath = collection == "photos" ? contentPath : "content/\(collection)"
        
        let uniqueTags = Array(Set(tags)).sorted()
        let data = try JSONEncoder().encode(uniqueTags)
        guard let content = String(data: data, encoding: .utf8) else {
            throw PublishError.invalidResponse
        }
        
        let tagsPath = "\(collectionPath)/tags.json"
        try await commitFileToGitHub(
            path: tagsPath,
            content: content,
            message: "Update \(collection) tags.json"
        )
    }
    
    // MARK: - Publishing
    
    func publishPhotos(_ photos: [PhotoItem], title: String, tags: [String], asGallery: Bool, imageScale: ImageScale = .optimized) async throws {
        guard !githubToken.isEmpty else {
            throw PublishError.notAuthenticated
        }
        
        // Load config if not already loaded
        if cmsConfig == nil {
            await loadCMSConfig()
        }
        
        // Validate we have config
        guard let config = cmsConfig else {
            throw PublishError.configError(configLoadError ?? "Failed to load CMS configuration")
        }
        
        // Load current tags and determine if we need to update tags.json
        let currentTags = await loadTags(for: "photos")
        let newTags = Set(tags).subtracting(Set(currentTags))
        let shouldUpdateTags = !newTags.isEmpty
        let updatedTagsList = shouldUpdateTags ? (currentTags + Array(newTags)).sorted() : []
        
        if asGallery && photos.count > 1 {
            try await publishAsGallery(photos: photos, title: title, tags: tags, config: config, imageScale: imageScale, updatedTags: shouldUpdateTags ? updatedTagsList : nil)
        } else {
            for photo in photos {
                try await publishSinglePhoto(photo: photo, title: title, tags: tags, config: config, imageScale: imageScale, updatedTags: shouldUpdateTags ? updatedTagsList : nil)
            }
        }
    }
    
    func publishNote(title: String, body: String, tags: [String]) async throws {
        guard !githubToken.isEmpty else {
            throw PublishError.notAuthenticated
        }
        
        // Load config if not already loaded
        if cmsConfig == nil {
            await loadCMSConfig()
        }
        
        // Validate we have config
        guard let config = cmsConfig else {
            throw PublishError.configError(configLoadError ?? "Failed to load CMS configuration")
        }
        
        guard let collection = config.notesCollection else {
            throw PublishError.configError("No notes collection found in config")
        }
        
        // Load current tags and determine if we need to update tags.json
        let currentTags = await loadTags(for: "notes")
        let newTags = Set(tags).subtracting(Set(currentTags))
        let shouldUpdateTags = !newTags.isEmpty
        let updatedTagsList = shouldUpdateTags ? (currentTags + Array(newTags)).sorted() : []
        
        let date = Date()
        let entryPath = generateEntryPath(title: title, date: date, collection: collection)
        let markdownPath = entryPath.hasSuffix("/index") ? "\(entryPath).md" : "\(entryPath).md"
        
        var yaml = "---\n"
        yaml += "title: \"\(title)\"\n"
        yaml += "date: \(ISO8601DateFormatter().string(from: date))\n"
        
        if !tags.isEmpty {
            yaml += "tags:\n"
            for tag in tags {
                yaml += "  - \(tag)\n"
            }
        }
        
        yaml += "---\n\n"
        yaml += body
        
        // Prepare files for commit
        var filesToCommit: [(path: String, content: String, isBase64: Bool)] = [
            (path: markdownPath, content: yaml, isBase64: false)
        ]
        
        // Add tags.json if needed
        if shouldUpdateTags {
            let tagsPath = "content/notes/tags.json"
            let data = try JSONEncoder().encode(updatedTagsList)
            guard let tagsContent = String(data: data, encoding: .utf8) else {
                throw PublishError.invalidResponse
            }
            filesToCommit.append((path: tagsPath, content: tagsContent, isBase64: false))
            Logger.network.debug("- Tags: \(tagsPath)")
        }
        
        Logger.network.info("Preparing to commit note")
        Logger.network.debug("- Markdown: \(markdownPath)")
        
        // Commit all files in a single transaction
        try await commitMultipleFiles(
            files: filesToCommit,
            message: "Add note: \(title)"
        )
    }
    
    private func publishSinglePhoto(photo: PhotoItem, title: String, tags: [String], config: DecapCMSConfig, imageScale: ImageScale, updatedTags: [String]? = nil) async throws {
        guard let asset = photo.asset else {
            throw PublishError.networkError("No asset available")
        }
        
        guard let collection = config.photoCollection else {
            throw PublishError.configError("No photos collection found in config")
        }
        
        // Get EXIF creation date from the image file itself
        let date = await getEXIFDate(for: asset) ?? asset.creationDate ?? Date()
        
        // Get image data with scaling and JPEG conversion
        let imageData = try await getImageData(for: asset, scale: imageScale)
        
        // Get filename from asset resources
        let resources = PHAssetResource.assetResources(for: asset)
        let originalFilename = resources.first?.originalFilename ?? "photo-\(Date().timeIntervalSince1970).jpg"
        let filename: String
        if originalFilename.lowercased().hasSuffix(".heic") {
            filename = String(originalFilename.dropLast(5)) + ".jpg"
        } else if !originalFilename.lowercased().hasSuffix(".jpg") && !originalFilename.lowercased().hasSuffix(".jpeg") {
            filename = originalFilename + ".jpg"
        } else {
            filename = originalFilename
        }
        
        // Generate the entry path
        let entryPath = generateEntryPath(title: title, date: date, collection: collection)
        
        // Determine image path and reference
        let imagePath: String
        let imageReference: String
        
        if collection.usesMediaInEntry {
            let entryDir = entryPath.hasSuffix("/index") ? 
                String(entryPath.dropLast(6)) : 
                entryPath
            imagePath = "\(entryDir)/\(filename)"
            imageReference = collection.publicFolder.isEmpty ? filename : "\(collection.publicFolder)/\(filename)"
        } else {
            // Use the collection's mediaFolder, or fallback to global config mediaFolder if not specified
            let mediaFolder = !collection.mediaFolder.isEmpty ? collection.mediaFolder : config.mediaFolder
            imagePath = "\(mediaFolder)/\(filename)"
            imageReference = "\(collection.publicFolder.isEmpty ? config.publicFolder : collection.publicFolder)/\(filename)"
        }
        
        let markdownPath = entryPath.hasSuffix("/index") ? "\(entryPath).md" : "\(entryPath).md"
        
        let frontmatter = createFrontmatter(
            title: title,
            tags: tags,
            date: date,
            image: imageReference,
            metadata: photo.metadata
        )
        
        // Prepare files for commit
        var filesToCommit: [(path: String, content: String, isBase64: Bool)] = [
            (path: imagePath, content: imageData.base64EncodedString(), isBase64: true),
            (path: markdownPath, content: frontmatter, isBase64: false)
        ]
        
        // Add tags.json if needed
        if let updatedTags = updatedTags {
            let tagsPath = "\(contentPath)/tags.json"
            let data = try JSONEncoder().encode(updatedTags)
            guard let tagsContent = String(data: data, encoding: .utf8) else {
                throw PublishError.invalidResponse
            }
            filesToCommit.append((path: tagsPath, content: tagsContent, isBase64: false))
            Logger.network.debug("- Tags: \(tagsPath)")
        }
        
        Logger.network.info("Preparing to commit photo")
        Logger.network.debug("- Image: \(imagePath)")
        Logger.network.debug("- Markdown: \(markdownPath)")
        Logger.performance.info("Image size: \(imageData.count) bytes")
        
        // Commit all files in a single transaction
        try await commitMultipleFiles(
            files: filesToCommit,
            message: "Add photo: \(title)"
        )
    }
    
    private func publishAsGallery(photos: [PhotoItem], title: String, tags: [String], config: DecapCMSConfig, imageScale: ImageScale, updatedTags: [String]? = nil) async throws {
        guard let collection = config.photoCollection else {
            throw PublishError.configError("No photos collection found in config")
        }
        
        // Get EXIF date from first photo
        let firstAsset = photos.first?.asset
        let date = await getEXIFDate(for: firstAsset) ?? firstAsset?.creationDate ?? Date()
        var imageReferences: [String] = []
        var filesToCommit: [(path: String, content: String, isBase64: Bool)] = []
        
        // Generate the entry path
        let entryPath = generateEntryPath(title: title, date: date, collection: collection)
        
        // Prepare all images
        for (index, photo) in photos.enumerated() {
            guard let asset = photo.asset else { continue }
            
            let imageData = try await getImageData(for: asset, scale: imageScale)
            
            // Get filename from asset resources
            let resources = PHAssetResource.assetResources(for: asset)
            let originalFilename = resources.first?.originalFilename ?? "gallery-\(Date().timeIntervalSince1970)-\(index).jpg"
            let filename: String
            if originalFilename.lowercased().hasSuffix(".heic") {
                filename = String(originalFilename.dropLast(5)) + ".jpg"
            } else if !originalFilename.lowercased().hasSuffix(".jpg") && !originalFilename.lowercased().hasSuffix(".jpeg") {
                filename = originalFilename + ".jpg"
            } else {
                filename = originalFilename
            }
            
            let imagePath: String
            let imageReference: String
            
            if collection.usesMediaInEntry {
                let entryDir = entryPath.hasSuffix("/index") ? 
                    String(entryPath.dropLast(6)) : 
                    entryPath
                imagePath = "\(entryDir)/\(filename)"
                imageReference = collection.publicFolder.isEmpty ? filename : "\(collection.publicFolder)/\(filename)"
            } else {
                // Use the collection's mediaFolder, or fallback to global config mediaFolder if not specified
                let mediaFolder = !collection.mediaFolder.isEmpty ? collection.mediaFolder : config.mediaFolder
                imagePath = "\(mediaFolder)/\(filename)"
                imageReference = "\(collection.publicFolder.isEmpty ? config.publicFolder : collection.publicFolder)/\(filename)"
            }
            
            filesToCommit.append((path: imagePath, content: imageData.base64EncodedString(), isBase64: true))
            imageReferences.append(imageReference)
            
            Logger.network.debug("Prepared gallery image \(index + 1): \(imagePath)")
        }
        
        // Create markdown file with gallery frontmatter
        let markdownPath = entryPath.hasSuffix("/index") ? "\(entryPath).md" : "\(entryPath).md"
        let frontmatter = createGalleryFrontmatter(
            title: title,
            tags: tags,
            date: date,
            images: imageReferences
        )
        
        filesToCommit.append((path: markdownPath, content: frontmatter, isBase64: false))
        Logger.network.debug("Prepared markdown: \(markdownPath)")
        
        // Add tags.json if needed
        if let updatedTags = updatedTags {
            let tagsPath = "\(contentPath)/tags.json"
            let data = try JSONEncoder().encode(updatedTags)
            guard let tagsContent = String(data: data, encoding: .utf8) else {
                throw PublishError.invalidResponse
            }
            filesToCommit.append((path: tagsPath, content: tagsContent, isBase64: false))
            Logger.network.debug("- Tags: \(tagsPath)")
        }
        
        // Commit all files in a single transaction
        try await commitMultipleFiles(
            files: filesToCommit,
            message: "Add gallery: \(title)"
        )
    }
    
    // MARK: - Frontmatter Generation
    
    private func createFrontmatter(title: String, tags: [String], date: Date, image: String, metadata: PhotoMetadata?) -> String {
        var yaml = "---\n"
        yaml += "title: \"\(title)\"\n"
        yaml += "date: \(ISO8601DateFormatter().string(from: date))\n"
        yaml += "image: \(image)\n"
        
        if !tags.isEmpty {
            yaml += "tags:\n"
            for tag in tags {
                yaml += "  - \(tag)\n"
            }
        }
        
        if let metadata = metadata {
            if let camera = metadata.cameraModel {
                yaml += "camera: \"\(camera)\"\n"
            }
            if let aperture = metadata.aperture {
                yaml += "aperture: \(aperture)\n"
            }
            if let iso = metadata.iso {
                yaml += "iso: \(iso)\n"
            }
            if let shutter = metadata.shutterSpeed {
                yaml += "shutter: \"\(shutter)\"\n"
            }
            if let location = metadata.location {
                yaml += "location: \"\(location)\"\n"
            }
        }
        
        yaml += "---\n\n"
        return yaml
    }
    
    private func createGalleryFrontmatter(title: String, tags: [String], date: Date, images: [String]) -> String {
        var yaml = "---\n"
        yaml += "title: \"\(title)\"\n"
        yaml += "date: \(ISO8601DateFormatter().string(from: date))\n"
        
        if !tags.isEmpty {
            yaml += "tags:\n"
            for tag in tags {
                yaml += "  - \(tag)\n"
            }
        }
        
        // Add main image field (first image) - template will discover all images in directory
        if let firstImage = images.first {
            yaml += "image: \(firstImage)\n"
        }
        
        yaml += "---\n\n"
        
        return yaml
    }
    
    // MARK: - GitHub API
    
    private func fetchFileFromGitHub(path: String) async throws -> String {
        let url = URL(string: "\(apiBase)/repos/\(githubRepo)/contents/\(path)?ref=\(githubBranch)")!
        var request = URLRequest(url: url)
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        Logger.network.debug("Fetching file from GitHub: \(path)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PublishError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                Logger.network.info("File not found: \(path)")
                return ""
            }
            Logger.network.error("Failed to fetch file: HTTP \(httpResponse.statusCode)")
            throw PublishError.gitHubError("HTTP \(httpResponse.statusCode)")
        }
        
        struct FileResponse: Codable {
            let content: String
            let encoding: String
        }
        
        let fileResponse = try JSONDecoder().decode(FileResponse.self, from: data)
        
        if fileResponse.encoding == "base64",
           let decodedData = Data(base64Encoded: fileResponse.content.replacingOccurrences(of: "\n", with: "")),
           let content = String(data: decodedData, encoding: .utf8) {
            return content
        }
        
        return ""
    }
    
    private func commitFileToGitHub(path: String, content: String, message: String, isBase64: Bool = false) async throws {
        Logger.network.debug("Committing file to GitHub: \(path), isBase64: \(isBase64)")
        
        // Get current file SHA if it exists
        var sha: String?
        do {
            let url = URL(string: "\(apiBase)/repos/\(githubRepo)/contents/\(path)?ref=\(githubBranch)")!
            var request = URLRequest(url: url)
            request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                struct FileInfo: Codable {
                    let sha: String
                }
                let fileInfo = try JSONDecoder().decode(FileInfo.self, from: data)
                sha = fileInfo.sha
            }
        } catch {
            // File doesn't exist, that's okay
        }
        
        // Create or update file
        let url = URL(string: "\(apiBase)/repos/\(githubRepo)/contents/\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        struct CommitRequest: Codable {
            let message: String
            let content: String
            let branch: String
            let sha: String?
        }
        
        let contentToCommit = isBase64 ? content : content.data(using: .utf8)!.base64EncodedString()
        
        let commitRequest = CommitRequest(
            message: message,
            content: contentToCommit,
            branch: githubBranch,
            sha: sha
        )
        
        request.httpBody = try JSONEncoder().encode(commitRequest)
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PublishError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Attempt to decode error message from GitHub
            if let errorJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let message = errorJson["message"] as? String {
                Logger.network.error("GitHub API error: \(message)")
                throw PublishError.gitHubError("HTTP \(httpResponse.statusCode): \(message)")
            }
            Logger.network.error("GitHub API error: HTTP \(httpResponse.statusCode)")
            throw PublishError.gitHubError("HTTP \(httpResponse.statusCode)")
        }
        
        Logger.network.info("Successfully committed file to GitHub: \(path)")
    }
    
    private func commitMultipleFiles(files: [(path: String, content: String, isBase64: Bool)], message: String) async throws {
        Logger.network.info("commitMultipleFiles called with \(files.count) files")
        
        // Step 1: Get the latest commit SHA
        let refUrl = URL(string: "\(apiBase)/repos/\(githubRepo)/git/ref/heads/\(githubBranch)")!
        var refRequest = URLRequest(url: refUrl)
        refRequest.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        refRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        refRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let (refData, refResponse) = try await URLSession.shared.data(for: refRequest)
        guard let httpResponse = refResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PublishError.gitHubError("Failed to get branch reference")
        }
        
        struct RefResponse: Codable {
            let object: GitObject
            struct GitObject: Codable {
                let sha: String
            }
        }
        
        let refInfo = try JSONDecoder().decode(RefResponse.self, from: refData)
        let latestCommitSha = refInfo.object.sha
        Logger.network.debug("Latest commit SHA: \(latestCommitSha)")
        
        // Step 2: Get the tree SHA from the latest commit
        let commitUrl = URL(string: "\(apiBase)/repos/\(githubRepo)/git/commits/\(latestCommitSha)")!
        var commitRequest = URLRequest(url: commitUrl)
        commitRequest.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        commitRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        commitRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let (commitData, commitResponse) = try await URLSession.shared.data(for: commitRequest)
        guard let commitHttpResponse = commitResponse as? HTTPURLResponse, commitHttpResponse.statusCode == 200 else {
            throw PublishError.gitHubError("Failed to get commit")
        }
        
        struct CommitResponse: Codable {
            let tree: Tree
            struct Tree: Codable {
                let sha: String
            }
        }
        
        let commitInfo = try JSONDecoder().decode(CommitResponse.self, from: commitData)
        let baseTreeSha = commitInfo.tree.sha
        Logger.network.debug("Base tree SHA: \(baseTreeSha)")
        
        // Step 3: Create blobs for each file
        var treeItems: [[String: String]] = []
        
        for file in files {
            let blobUrl = URL(string: "\(apiBase)/repos/\(githubRepo)/git/blobs")!
            var blobRequest = URLRequest(url: blobUrl)
            blobRequest.httpMethod = "POST"
            blobRequest.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
            blobRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            blobRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            blobRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            
            struct BlobRequest: Codable {
                let content: String
                let encoding: String
            }
            
            let blobContent = file.isBase64 ? file.content : file.content.data(using: .utf8)!.base64EncodedString()
            let blobRequestBody = BlobRequest(content: blobContent, encoding: "base64")
            blobRequest.httpBody = try JSONEncoder().encode(blobRequestBody)
            
            let (blobData, blobResponse) = try await URLSession.shared.data(for: blobRequest)
            guard let blobHttpResponse = blobResponse as? HTTPURLResponse, blobHttpResponse.statusCode == 201 else {
                throw PublishError.gitHubError("Failed to create blob for \(file.path)")
            }
            
            struct BlobResponse: Codable {
                let sha: String
            }
            
            let blobInfo = try JSONDecoder().decode(BlobResponse.self, from: blobData)
            Logger.network.debug("Created blob for \(file.path): \(blobInfo.sha)")
            
            treeItems.append([
                "path": file.path,
                "mode": "100644",
                "type": "blob",
                "sha": blobInfo.sha
            ])
        }
        
        // Step 4: Create a new tree
        let treeUrl = URL(string: "\(apiBase)/repos/\(githubRepo)/git/trees")!
        var treeRequest = URLRequest(url: treeUrl)
        treeRequest.httpMethod = "POST"
        treeRequest.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        treeRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        treeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        treeRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let treeRequestBody: [String: Any] = [
            "base_tree": baseTreeSha,
            "tree": treeItems
        ]
        
        treeRequest.httpBody = try JSONSerialization.data(withJSONObject: treeRequestBody)
        
        let (treeData, treeResponse) = try await URLSession.shared.data(for: treeRequest)
        guard let treeHttpResponse = treeResponse as? HTTPURLResponse, treeHttpResponse.statusCode == 201 else {
            throw PublishError.gitHubError("Failed to create tree")
        }
        
        struct TreeResponse: Codable {
            let sha: String
        }
        
        let treeInfo = try JSONDecoder().decode(TreeResponse.self, from: treeData)
        let newTreeSha = treeInfo.sha
        Logger.network.debug("Created tree: \(newTreeSha)")
        
        // Step 5: Create a new commit
        let newCommitUrl = URL(string: "\(apiBase)/repos/\(githubRepo)/git/commits")!
        var newCommitRequest = URLRequest(url: newCommitUrl)
        newCommitRequest.httpMethod = "POST"
        newCommitRequest.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        newCommitRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        newCommitRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        newCommitRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        struct NewCommitRequest: Codable {
            let message: String
            let tree: String
            let parents: [String]
        }
        
        let newCommitBody = NewCommitRequest(
            message: message,
            tree: newTreeSha,
            parents: [latestCommitSha]
        )
        
        newCommitRequest.httpBody = try JSONEncoder().encode(newCommitBody)
        
        let (newCommitData, newCommitResponse) = try await URLSession.shared.data(for: newCommitRequest)
        guard let newCommitHttpResponse = newCommitResponse as? HTTPURLResponse, newCommitHttpResponse.statusCode == 201 else {
            throw PublishError.gitHubError("Failed to create commit")
        }
        
        struct NewCommitResponse: Codable {
            let sha: String
        }
        
        let newCommitInfo = try JSONDecoder().decode(NewCommitResponse.self, from: newCommitData)
        let newCommitSha = newCommitInfo.sha
        Logger.network.debug("Created commit: \(newCommitSha)")
        
        // Step 6: Update the branch reference
        let updateRefUrl = URL(string: "\(apiBase)/repos/\(githubRepo)/git/refs/heads/\(githubBranch)")!
        var updateRefRequest = URLRequest(url: updateRefUrl)
        updateRefRequest.httpMethod = "PATCH"
        updateRefRequest.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        updateRefRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        updateRefRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        updateRefRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        struct UpdateRefRequest: Codable {
            let sha: String
        }
        
        let updateRefBody = UpdateRefRequest(sha: newCommitSha)
        updateRefRequest.httpBody = try JSONEncoder().encode(updateRefBody)
        
        let (_, updateRefResponse) = try await URLSession.shared.data(for: updateRefRequest)
        guard let updateRefHttpResponse = updateRefResponse as? HTTPURLResponse, updateRefHttpResponse.statusCode == 200 else {
            throw PublishError.gitHubError("Failed to update branch reference")
        }
        
        Logger.network.info("Successfully committed \(files.count) files to GitHub")
    }
    
    // MARK: - Helpers
    
    private func generateSlug(title: String, date: Date, template: String) -> String {
        let dateFormatter = DateFormatter()
        
        var slug = template
        
        // Replace common Decap CMS slug patterns
        // {{year}} {{month}} {{day}} {{hour}} {{minute}} {{second}} {{slug}} {{fields.title}}
        dateFormatter.dateFormat = "yyyy"
        slug = slug.replacingOccurrences(of: "{{year}}", with: dateFormatter.string(from: date))
        
        dateFormatter.dateFormat = "MM"
        slug = slug.replacingOccurrences(of: "{{month}}", with: dateFormatter.string(from: date))
        
        dateFormatter.dateFormat = "dd"
        slug = slug.replacingOccurrences(of: "{{day}}", with: dateFormatter.string(from: date))
        
        dateFormatter.dateFormat = "HH"
        slug = slug.replacingOccurrences(of: "{{hour}}", with: dateFormatter.string(from: date))
        
        dateFormatter.dateFormat = "mm"
        slug = slug.replacingOccurrences(of: "{{minute}}", with: dateFormatter.string(from: date))
        
        dateFormatter.dateFormat = "ss"
        slug = slug.replacingOccurrences(of: "{{second}}", with: dateFormatter.string(from: date))
        
        // Replace slug and title placeholders
        let slugifiedTitle = slugify(title)
        slug = slug.replacingOccurrences(of: "{{slug}}", with: slugifiedTitle)
        slug = slug.replacingOccurrences(of: "{{fields.title}}", with: slugifiedTitle)
        
        return slug
    }
    
    private func generateEntryPath(title: String, date: Date, collection: DecapCMSConfig.CollectionConfig) -> String {
        // If collection has a path template, use it
        if let pathTemplate = collection.path {
            Logger.persistence.debug("Using path template: \(pathTemplate)")
            let pathWithVariables = generateSlug(title: title, date: date, template: pathTemplate)
            let fullPath = "\(collection.folder)/\(pathWithVariables)"
            Logger.persistence.debug("Generated path: \(fullPath)")
            return fullPath
        }
        
        // Otherwise use simple slug
        Logger.persistence.debug("No path template, using slug template or simple slugify")
        let slug = collection.slugTemplate != nil ? 
            generateSlug(title: title, date: date, template: collection.slugTemplate!) : 
            slugify(title)
        let fullPath = "\(collection.folder)/\(slug)"
        Logger.persistence.debug("Generated path: \(fullPath)")
        return fullPath
    }
    
    enum ImageScale {
        case original      // 100%
        case optimized     // 50%
        case minimal       // 25%
        
        var scale: CGFloat {
            switch self {
            case .original: return 1.0
            case .optimized: return 0.5
            case .minimal: return 0.25
            }
        }
        
        var compressionQuality: CGFloat {
            switch self {
            case .original: return 0.9
            case .optimized: return 0.85
            case .minimal: return 0.8
            }
        }
    }
    
    private func getEXIFDate(for asset: PHAsset?) async -> Date? {
        guard let asset = asset else { return nil }
        
        return await withCheckedContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            
            asset.requestContentEditingInput(with: options) { input, _ in
                guard let url = input?.fullSizeImageURL,
                      let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
                      let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
                      let dateString = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Parse EXIF date format: "2024:01:17 14:23:45"
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                let date = formatter.date(from: dateString)
                continuation.resume(returning: date)
            }
        }
    }
    
    private func getImageData(for asset: PHAsset, scale: ImageScale = .optimized) async throws -> Data {
        // Get the full resolution UIImage
        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.resizeMode = .exact
            
            let targetSize: CGSize
            if scale == .original {
                // Request full size
                targetSize = PHImageManagerMaximumSize
            } else {
                // Calculate scaled size
                let pixelWidth = CGFloat(asset.pixelWidth)
                let pixelHeight = CGFloat(asset.pixelHeight)
                targetSize = CGSize(
                    width: pixelWidth * scale.scale,
                    height: pixelHeight * scale.scale
                )
            }
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let image = image {
                    continuation.resume(returning: image)
                } else if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: PublishError.networkError("Failed to get image"))
                }
            }
        }
        
        // Convert to JPEG data (this automatically handles HEIC conversion)
        guard let jpegData = image.jpegData(compressionQuality: scale.compressionQuality) else {
            throw PublishError.networkError("Failed to convert image to JPEG")
        }
        
        return jpegData
    }
    
    private func slugify(_ string: String) -> String {
        let lowercase = string.lowercased()
        let alphanumeric = lowercase.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "-")
        let cleaned = alphanumeric.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
