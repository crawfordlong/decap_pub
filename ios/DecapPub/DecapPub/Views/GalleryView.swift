import SwiftUI

struct GalleryView: View {
    @ObservedObject var viewModel: PhotoGalleryViewModel
    @State private var selectedPhoto: PhotoItem?
    @State private var selectedPhotos: Set<String> = []
    @State private var isSelecting = false

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.photos) { photo in
                    PhotoThumbnailView(
                        photo: photo,
                        isSelected: selectedPhotos.contains(photo.id),
                        isSelecting: isSelecting
                    )
                    .onTapGesture {
                        if isSelecting {
                            toggleSelection(photo)
                        } else {
                            selectedPhoto = photo
                        }
                    }
                    .onLongPressGesture {
                        showActions(for: photo)
                    }
                    .contextMenu {
                        photoContextMenu(for: photo)
                    }
                }
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo)
        }
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Cancel") {
                            isSelecting = false
                            selectedPhotos.removeAll()
                        }
                        Spacer()
                        Text("\(selectedPhotos.count) selected")
                        Spacer()
                        Button("Send") {
                            sendSelectedPhotos()
                        }
                        .disabled(selectedPhotos.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadPhotos()
        }
    }

    private func toggleSelection(_ photo: PhotoItem) {
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
        } else {
            selectedPhotos.insert(photo.id)
        }
    }

    private func showActions(for photo: PhotoItem) {
        // Long press initiates selection mode
        isSelecting = true
        selectedPhotos.insert(photo.id)
    }

    @ViewBuilder
    private func photoContextMenu(for photo: PhotoItem) -> some View {
        Button {
            Task {
                await viewModel.sendToSite(photos: [photo])
            }
        } label: {
            Label("Send to \(viewModel.siteName)", systemImage: "arrow.up.circle")
        }

        Button {
            isSelecting = true
            selectedPhotos.insert(photo.id)
        } label: {
            Label("Select Multiple", systemImage: "checkmark.circle")
        }

        Button {
            selectedPhoto = photo
        } label: {
            Label("View Details", systemImage: "info.circle")
        }
    }

    private func sendSelectedPhotos() {
        let photosToSend = viewModel.photos.filter { selectedPhotos.contains($0.id) }
        Task {
            await viewModel.sendToSite(photos: photosToSend)
            isSelecting = false
            selectedPhotos.removeAll()
        }
    }
}

#Preview {
    NavigationStack {
        GalleryView(viewModel: PhotoGalleryViewModel())
    }
}
