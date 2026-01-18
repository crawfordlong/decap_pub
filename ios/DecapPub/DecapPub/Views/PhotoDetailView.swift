import SwiftUI
import Photos
import os.log

@available(iOS 26.0, *)
struct PhotoDetailView: View {
    let photo: PhotoItem
    let publishManager: PublishManager
    @ObservedObject var viewModel: PhotoGalleryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingMetadata = false
    @State private var showingPublishSheet = false
    @State private var fullImage: UIImage?
    @State private var isLoadingImage = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                GeometryReader { geometry in
                    if let image = fullImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        ProgressView()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .background(Color.black)
                
                DetailToolbar(
                    onDismiss: { dismiss() },
                    onShowMetadata: { showingMetadata = true }
                )
                
                VStack {
                    Spacer()
                    
                    DetailBottomBar(
                        onPublish: { showingPublishSheet = true }
                    )
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingMetadata) {
                MetadataView(photo: photo, viewModel: viewModel)
            }
            .sheet(isPresented: $showingPublishSheet) {
                PublishView(
                    publishManager: publishManager,
                    photos: [photo],
                    mode: .single
                )
            }
        }
        .preferredColorScheme(.dark)
        .task(id: photo.id) {
            await loadFullImageIfNeeded()
        }
        .onDisappear {
            fullImage = nil
        }
    }
    
    private func loadFullImageIfNeeded() async {
        guard !isLoadingImage else { return }
        
        isLoadingImage = true
        fullImage = await viewModel.loadFullImage(for: photo)
        isLoadingImage = false
    }
}

@available(iOS 26.0, *)
struct DetailBottomBar: View {
    let onPublish: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Button {
                onPublish()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                    Text("Publish Now")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .background(.blue.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

@available(iOS 26.0, *)
struct DetailToolbar: View {
    let onDismiss: () -> Void
    let onShowMetadata: () -> Void
    
    var body: some View {
        HStack(spacing: 20.0) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Button {
                onShowMetadata()
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }
}

@available(iOS 26.0, *)
struct MetadataView: View {
    let photo: PhotoItem
    let viewModel: PhotoGalleryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var metadata: PhotoMetadata?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading metadata...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else if let metadata = metadata {
                    List {
                        Section("File Info") {
                            LabeledContent("Filename", value: metadata.filename)
                            LabeledContent("Date", value: metadata.creationDate?.formatted() ?? "Unknown")
                            LabeledContent("Size", value: metadata.formattedFileSize)
                        }

                        if let camera = metadata.cameraModel {
                            Section("Camera") {
                                LabeledContent("Model", value: camera)
                                if let lens = metadata.lensModel {
                                    LabeledContent("Lens", value: lens)
                                }
                            }
                        }

                        if metadata.hasExposureInfo {
                            Section("Exposure") {
                                if let aperture = metadata.aperture {
                                    LabeledContent("Aperture", value: "f/\(aperture)")
                                }
                                if let shutter = metadata.shutterSpeed {
                                    LabeledContent("Shutter", value: shutter)
                                }
                                if let iso = metadata.iso {
                                    LabeledContent("ISO", value: "\(iso)")
                                }
                            }
                        }

                        if let location = metadata.location {
                            Section("Location") {
                                LabeledContent("Coordinates", value: location)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                } else {
                    ContentUnavailableView(
                        "No Metadata Available",
                        systemImage: "info.circle",
                        description: Text("Metadata could not be loaded for this photo.")
                    )
                    .background(Color.black)
                }
            }
            .navigationTitle("Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await loadMetadata()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func loadMetadata() async {
        if let existing = photo.metadata {
            metadata = existing
            return
        }
        
        isLoading = true
        metadata = await viewModel.loadMetadata(for: photo)
        isLoading = false
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        PhotoDetailView(
            photo: PhotoItem(id: "1", asset: nil),
            publishManager: PublishManager(),
            viewModel: PhotoGalleryViewModel()
        )
    } else {
        Text("Requires iOS 26.0")
    }
}
