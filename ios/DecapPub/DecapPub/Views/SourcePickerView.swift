import SwiftUI
import PhotosUI

struct SourcePickerView: View {
    @ObservedObject var viewModel: PhotoGalleryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Photo Library") {
                    Button {
                        viewModel.selectSource(.photoLibrary)
                        dismiss()
                    } label: {
                        Label("All Photos", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        viewModel.selectSource(.recents)
                        dismiss()
                    } label: {
                        Label("Recents", systemImage: "clock")
                    }

                    Button {
                        viewModel.selectSource(.favorites)
                        dismiss()
                    } label: {
                        Label("Favorites", systemImage: "heart")
                    }
                }

                Section("Albums") {
                    ForEach(viewModel.albums) { album in
                        Button {
                            viewModel.selectSource(.album(album.id))
                            dismiss()
                        } label: {
                            Label(album.title, systemImage: "folder")
                        }
                    }
                }

                Section("Files") {
                    Button {
                        viewModel.showFilePicker()
                        dismiss()
                    } label: {
                        Label("Browse Files...", systemImage: "folder.badge.plus")
                    }
                }
            }
            .navigationTitle("Choose Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SourcePickerView(viewModel: PhotoGalleryViewModel())
}
