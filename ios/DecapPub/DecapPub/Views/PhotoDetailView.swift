import SwiftUI

struct PhotoDetailView: View {
    let photo: PhotoItem
    @Environment(\.dismiss) private var dismiss
    @State private var showingMetadata = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let image = photo.fullImage {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingMetadata = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingMetadata) {
                MetadataView(photo: photo)
            }
        }
    }
}

struct MetadataView: View {
    let photo: PhotoItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let metadata = photo.metadata {
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
                } else {
                    Text("No metadata available")
                        .foregroundColor(.secondary)
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
        }
    }
}

#Preview {
    PhotoDetailView(photo: PhotoItem(id: "1", asset: nil))
}
