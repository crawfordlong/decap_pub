import SwiftUI
import PhotosUI

@available(iOS 26.0, *)
struct ContentView: View {
    @StateObject private var viewModel = PhotoGalleryViewModel()
    @StateObject private var publishManager = PublishManager()
    @State private var showingSettings = false
    @State private var showingSourcePicker = false
    @State private var showingNoteComposer = false
    @State private var isSelecting = false

    var body: some View {
        NavigationStack {
            ZStack {
                GalleryView(
                    viewModel: viewModel,
                    publishManager: publishManager,
                    isSelecting: $isSelecting
                )
                .navigationBarHidden(true)
                
                VStack {
                    Spacer()
                    if !isSelecting {
                        GlassToolbarView(
                            showingSettings: $showingSettings,
                            showingSourcePicker: $showingSourcePicker,
                            showingNoteComposer: $showingNoteComposer
                        )
                        .padding(.bottom, 70)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingSourcePicker) {
                SourcePickerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingNoteComposer) {
                NoteComposerView(publishManager: publishManager)
            }
        }
        .preferredColorScheme(.dark)
    }
}

@available(iOS 26.0, *)
struct GlassToolbarView: View {
    @Binding var showingSettings: Bool
    @Binding var showingSourcePicker: Bool
    @Binding var showingNoteComposer: Bool
    @Namespace private var namespace
    @AppStorage("siteEndpoint") private var siteEndpoint = "https://crawfordlong.com"
    
    var body: some View {
        GlassEffectContainer(spacing: 20.0) {
            HStack(spacing: 20.0) {
                Button {
                    showingSourcePicker = true
                } label: {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                
                Spacer()
                
                Menu {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    
                    Button {
                        if let url = URL(string: siteEndpoint) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("View Site", systemImage: "safari")
                    }
                    
                    Divider()
                    
                    Button {
                        showingNoteComposer = true
                    } label: {
                        Label("New Note", systemImage: "note.text")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        ContentView()
    } else {
        Text("Requires iOS 26.0")
    }
}
