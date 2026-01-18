import SwiftUI

@available(iOS 26.0, *)
struct PhotoThumbnailView: View {
    let photo: PhotoItem
    let isSelected: Bool
    let isSelecting: Bool
    @ObservedObject var viewModel: PhotoGalleryViewModel
    
    @State private var thumbnail: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 120)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 120)
                    .overlay {
                        if isLoading {
                            ProgressView()
                        }
                    }
            }

            if isSelecting {
                ZStack {
                    Circle()
                        .fill(isSelected ? .white : .black.opacity(0.5))
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? .blue : .white)
                }
                .padding(8)
            }
        }
        .overlay {
            if isSelected && isSelecting {
                Rectangle()
                    .stroke(Color.blue, lineWidth: 3)
            }
        }
        .onAppear {
            loadThumbnailIfNeeded()
        }
        .onDisappear {
            // Images will be evicted from cache by LRU policy
            // No manual cleanup needed
        }
    }
    
    private func loadThumbnailIfNeeded() {
        // Check if already loaded
        guard thumbnail == nil else { return }
        
        // Prevent concurrent loads
        guard !isLoading else { return }
        isLoading = true
        
        Task { @MainActor in
            // Double-check after async boundary
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
}

#Preview {
    if #available(iOS 26.0, *) {
        HStack {
            PhotoThumbnailView(
                photo: PhotoItem(id: "1", asset: nil),
                isSelected: false,
                isSelecting: false,
                viewModel: PhotoGalleryViewModel()
            )
            .frame(width: 100, height: 100)

            PhotoThumbnailView(
                photo: PhotoItem(id: "2", asset: nil),
                isSelected: true,
                isSelecting: true,
                viewModel: PhotoGalleryViewModel()
            )
            .frame(width: 100, height: 100)
        }
    } else {
        Text("Requires iOS 26.0")
    }
}
