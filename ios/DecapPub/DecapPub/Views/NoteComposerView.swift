import SwiftUI

struct NoteComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var publishManager: PublishManager
    
    @State private var title = ""
    @State private var noteBody = ""
    @State private var selectedTags: Set<String> = []
    @State private var availableTags: [String] = []
    @State private var newTag = ""
    @State private var isPublishing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Note Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Note")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        TextField("Title", text: $title)
                            .autocapitalization(.words)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                        
                        TextEditor(text: $noteBody)
                            .frame(minHeight: 200)
                            .scrollContentBackground(.hidden)
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
                    .padding()
                    
                    // Tags Section
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
                    
                    // Selected Tags Section
                    if !selectedTags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Selected Tags")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(Array(selectedTags), id: \.self) { tag in
                                    TagChip(tag: tag) {
                                        selectedTags.remove(tag)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("New Note")
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
                    .disabled(title.isEmpty || noteBody.isEmpty || isPublishing)
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
            availableTags = await publishManager.loadTags(for: "notes")
        }
    }
    
    private func publish() {
        isPublishing = true
        
        Task {
            do {
                try await publishManager.publishNote(
                    title: title,
                    body: noteBody,
                    tags: Array(selectedTags)
                )
                
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

#Preview {
    if #available(iOS 26.0, *) {
        NoteComposerView(publishManager: PublishManager())
    } else {
        Text("Requires iOS 26.0")
    }
}
