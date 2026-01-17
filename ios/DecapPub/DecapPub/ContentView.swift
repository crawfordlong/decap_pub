import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = PhotoGalleryViewModel()
    @State private var showingSettings = false
    @State private var showingSourcePicker = false

    var body: some View {
        NavigationStack {
            GalleryView(viewModel: viewModel)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingSourcePicker = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $showingSourcePicker) {
                    SourcePickerView(viewModel: viewModel)
                }
        }
    }
}

#Preview {
    ContentView()
}
