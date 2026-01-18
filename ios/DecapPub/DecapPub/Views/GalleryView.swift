import SwiftUI

@available(iOS 26.0, *)
struct GalleryView: View {
    @ObservedObject var viewModel: PhotoGalleryViewModel
    @ObservedObject var publishManager: PublishManager
    @Binding var isSelecting: Bool
    @State private var selectedPhoto: PhotoItem?
    @State private var selectedPhotos: Set<String> = []
    @State private var showingPublishSheet = false
    @State private var photosToPublish: [PhotoItem] = []
    @State private var publishMode: PublishView.PublishMode = .single
    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 2)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(viewModel.photos.enumerated()), id: \.element.id) { index, photo in
                        PhotoThumbnailView(
                            photo: photo,
                            isSelected: selectedPhotos.contains(photo.id),
                            isSelecting: isSelecting,
                            viewModel: viewModel
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
                        .onAppear {
                            // Load more when we're near the end (10 items before the last)
                            if index >= viewModel.photos.count - 10 {
                                viewModel.loadNextPage()
                            }
                        }
                    }
                    
                    // Loading indicator at the bottom when fetching more
                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.white)
                                .padding()
                            Spacer()
                        }
                        .gridCellColumns(columns.count)
                    }
                }
                .padding(.bottom, isSelecting ? 180 : 140)
            }
            
            if viewModel.photos.isEmpty && !viewModel.isLoading {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("No Photos")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Tap the photo stack button to choose a source")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
            
            // Search bar at bottom - always visible
            if !isSelecting {
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.6))
                            .font(.system(size: 16))
                        
                        TextField("Search photos...", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.6))
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }
            
            if isSelecting {
                SelectionToolbar(
                    selectedCount: selectedPhotos.count,
                    onCancel: {
                        withAnimation(.spring(response: 0.3)) {
                            isSelecting = false
                            selectedPhotos.removeAll()
                        }
                    },
                    onSend: {
                        sendSelectedPhotos()
                    },
                    onPublishSeparate: {
                        publishSelectedPhotos(asGallery: false)
                    },
                    onPublishGallery: {
                        publishSelectedPhotos(asGallery: true)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo, publishManager: publishManager, viewModel: viewModel)
        }
        .sheet(isPresented: $showingPublishSheet) {
            PublishView(
                publishManager: publishManager,
                photos: photosToPublish,
                mode: publishMode
            )
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
            photosToPublish = [photo]
            publishMode = .single
            showingPublishSheet = true
        } label: {
            Label("Publish Now", systemImage: "arrow.up.circle.fill")
        }
        
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
        // Capture array snapshot to prevent mutation issues
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
    
    private func publishSelectedPhotos(asGallery: Bool) {
        // Capture array snapshot to prevent mutation issues
        let currentPhotos = viewModel.photos
        photosToPublish = currentPhotos.filter { selectedPhotos.contains($0.id) }
        publishMode = asGallery ? .groupedGallery : .batchSeparate
        showingPublishSheet = true
        
        withAnimation(.spring(response: 0.3)) {
            isSelecting = false
            selectedPhotos.removeAll()
        }
    }
}

@available(iOS 26.0, *)
struct SelectionToolbar: View {
    let selectedCount: Int
    let onCancel: () -> Void
    let onSend: () -> Void
    let onPublishSeparate: () -> Void
    let onPublishGallery: () -> Void
    @Namespace private var namespace
    
    var body: some View {
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: 20.0) {
                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    
                    Text("\(selectedCount) selected")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(in: .capsule)
                    
                    Spacer()
                    
                    Button {
                        onPublishSeparate()
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "square.grid.2x2")
                                .font(.body)
                            Text("Separate")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .frame(minWidth: 70)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                    .glassEffect(.regular.tint(.purple).interactive(), in: .rect(cornerRadius: 12))
                    .disabled(selectedCount == 0)
                    .opacity(selectedCount == 0 ? 0.5 : 1.0)
                    
                    Button {
                        onPublishGallery()
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.body)
                            Text("Gallery")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .frame(minWidth: 70)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                    .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: 12))
                    .disabled(selectedCount < 2)
                    .opacity(selectedCount < 2 ? 0.5 : 1.0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(.ultraThinMaterial)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        NavigationStack {
            GalleryView(
                viewModel: PhotoGalleryViewModel(),
                publishManager: PublishManager(),
                isSelecting: .constant(false)
            )
        }
        .preferredColorScheme(.dark)
    } else {
        Text("Requires iOS 26.0")
    }
}
