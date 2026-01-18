import SwiftUI
import Photos

struct PublishView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var publishManager: PublishManager
    
    let photos: [PhotoItem]
    let mode: PublishMode
    
    @State private var title = ""
    @State private var selectedTags: Set<String> = []
    @State private var availableTags: [String] = []
    @State private var newTag = ""
    @State private var isPublishing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var imageScale: PublishManager.ImageScale = .optimized
    @State private var isFirstEdit = true
    @FocusState private var titleFieldFocused: Bool
    
    enum PublishMode {
        case single
        case batchSeparate
        case groupedGallery
        
        func description(photoCount: Int) -> String {
            switch self {
            case .single: return "Publish Photo"
            case .batchSeparate: return "Publish \(photoCount) Photos Separately"
            case .groupedGallery: return "Publish as Gallery"
            }
        }
    }
    
    private var imageScaleText: String {
        switch imageScale {
        case .original:
            return "Original (100%)"
        case .optimized:
            return "Optimized (50%)"
        case .minimal:
            return "Minimal (25%)"
        }
    }
    
    private var titleField: some View {
        TextField("Title", text: $title)
            .autocapitalization(.words)
            .focused($titleFieldFocused)
            .onTapGesture {
                // On first tap, clear the prepopulated text
                if isFirstEdit && !title.isEmpty {
                    title = ""
                    isFirstEdit = false
                }
            }
            .onChange(of: title) { oldValue, newValue in
                // Mark as edited once user types
                if !newValue.isEmpty {
                    isFirstEdit = false
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
    }
    
    private var imageQualityMenu: some View {
        Menu {
            Picker("Image Quality", selection: $imageScale) {
                Text("Original (100%)").tag(PublishManager.ImageScale.original)
                Text("Optimized (50%)").tag(PublishManager.ImageScale.optimized)
                Text("Minimal (25%)").tag(PublishManager.ImageScale.minimal)
            }
        } label: {
            HStack {
                Text("Image Quality")
                    .foregroundStyle(.primary)
                Spacer()
                Text(imageScaleText)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            titleField
            
            imageQualityMenu
            
            if mode == .groupedGallery {
                Text("\(photos.count) photos will be published together")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if mode == .batchSeparate {
                Text("\(photos.count) separate entries will be created")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos, id: \.id) { photo in
                        AsyncThumbnailView(photo: photo)
                    }
                }
            }
        }
        .padding()
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            if !availableTags.isEmpty {
                VStack(spacing: 0) {
                    ForEach(availableTags, id: \.self) { tag in
                        Button {
                            toggleTag(tag)
                        } label: {
                            HStack {
                                Text(tag)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedTags.contains(tag) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding()
                        }
                        if tag != availableTags.last {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
            }
            
            HStack {
                TextField("Add new tag", text: $newTag)
                    .autocapitalization(.none)
                    .padding()
                
                Button {
                    addNewTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newTag.isEmpty)
                .padding(.trailing)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
        }
        .padding()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    detailsSection
                    
                    previewSection
                    
                    tagsSection
                }
            }
            .background(Color.black)
            .navigationTitle(mode.description(photoCount: photos.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        publish()
                    } label: {
                        if isPublishing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Publish")
                        }
                    }
                    .disabled(title.isEmpty || isPublishing)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .alert("Publishing Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadTags()
            if photos.count == 1, let asset = photos.first?.asset {
                // Get filename from asset resources
                let resources = PHAssetResource.assetResources(for: asset)
                if let filename = resources.first?.originalFilename {
                    title = filename.replacingOccurrences(of: ".jpg", with: "")
                        .replacingOccurrences(of: ".jpeg", with: "")
                        .replacingOccurrences(of: ".png", with: "")
                        .replacingOccurrences(of: ".heic", with: "")
                }
            }
        }
    }
    
    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
    
    private func addNewTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if !availableTags.contains(trimmed) {
            availableTags.append(trimmed)
        }
        selectedTags.insert(trimmed)
        newTag = ""
    }
    
    private func loadTags() {
        Task {
            availableTags = await publishManager.loadTags(for: "photos")
        }
    }
    
    private func publish() {
        isPublishing = true
        
        Task {
            do {
                switch mode {
                case .single, .groupedGallery:
                    try await publishManager.publishPhotos(
                        photos,
                        title: title,
                        tags: Array(selectedTags),
                        asGallery: mode == .groupedGallery,
                        imageScale: imageScale
                    )
                case .batchSeparate:
                    for photo in photos {
                        let photoTitle = title.isEmpty ? (photo.metadata?.filename ?? "Photo") : title
                        try await publishManager.publishPhotos(
                            [photo],
                            title: photoTitle,
                            tags: Array(selectedTags),
                            asGallery: false,
                            imageScale: imageScale
                        )
                    }
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isPublishing = false
                }
            }
        }
    }
}

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(tag)
                .font(.subheadline)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.blue.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.blue.opacity(0.5), lineWidth: 1)
        )
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: result.positions[index], proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - Helper Views

private struct AsyncThumbnailView: View {
    let photo: PhotoItem
    @State private var thumbnail: UIImage?
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        guard let asset = photo.asset else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        let loadedImage = await withCheckedContinuation { continuation in
            var hasResumed = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 160, height: 160),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                
                guard !hasResumed && !isDegraded else { return }
                hasResumed = true
                
                continuation.resume(returning: image)
            }
        }
        
        thumbnail = loadedImage
    }
}


