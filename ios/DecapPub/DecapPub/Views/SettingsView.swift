import SwiftUI

@available(iOS 26.0, *)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var publishManager = PublishManager()
    @AppStorage("siteEndpoint") private var siteEndpoint = "https://crawfordlong.com"
    @AppStorage("siteName") private var siteName = "Crawford Long"
    @AppStorage("githubRepo") private var githubRepo = "crawfordlong/crawfordlong-com-2025"
    @AppStorage("githubBranch") private var githubBranch = "trunk"
    @AppStorage("contentPath") private var contentPath = "content/photos"

    var body: some View {
        NavigationStack {
            Form {
                Section("Publication Endpoint") {
                    TextField("Site URL", text: $siteEndpoint)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    TextField("Site Name", text: $siteName)
                }

                Section("GitHub Repository") {
                    TextField("Repository (owner/repo)", text: $githubRepo)
                        .autocapitalization(.none)

                    TextField("Branch", text: $githubBranch)
                        .autocapitalization(.none)

                    TextField("Content Path", text: $contentPath)
                        .autocapitalization(.none)
                }

                Section("Authentication") {
                    NavigationLink("GitHub Account") {
                        GitHubAuthView()
                    }
                    
                    NavigationLink("CMS Configuration") {
                        CMSConfigView(publishManager: publishManager)
                    }
                }

                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        resetToDefaults()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func resetToDefaults() {
        siteEndpoint = "https://crawfordlong.com"
        siteName = "Crawford Long"
        githubRepo = "crawfordlong/crawfordlong-com-2025"
        githubBranch = "trunk"
        contentPath = "content/photos"
    }
}

@available(iOS 26.0, *)
struct GitHubAuthView: View {
    @State private var githubToken = ""
    @State private var isAuthenticated = false
    @State private var username = ""
    @State private var isVerifying = false

    var body: some View {
        Form {
            if isAuthenticated && !username.isEmpty {
                Section {
                    LabeledContent("Logged in as", value: username)
                    Button("Sign Out", role: .destructive) {
                        signOut()
                    }
                }
            } else {
                Section {
                    Text("Sign in with GitHub to publish photos to your site.")
                        .foregroundColor(.secondary)
                }

                Section("Personal Access Token") {
                    SecureField("GitHub Token", text: $githubToken)
                        .autocapitalization(.none)
                        .textContentType(.password)

                    Button {
                        verifyToken()
                    } label: {
                        if isVerifying {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Verify Token")
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(githubToken.isEmpty || isVerifying)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("GitHub Account")
        .onAppear {
            loadTokenFromKeychain()
            checkAuthStatus()
        }
    }

    private func checkAuthStatus() {
        if !githubToken.isEmpty {
            Task {
                await fetchUsername()
            }
        }
    }

    private func verifyToken() {
        isVerifying = true
        saveTokenToKeychain()
        Task {
            await fetchUsername()
            isVerifying = false
        }
    }
    
    private func fetchUsername() async {
        guard !githubToken.isEmpty else { return }
        
        do {
            let url = URL(string: "https://api.github.com/user")!
            var request = URLRequest(url: url)
            request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    isAuthenticated = false
                    username = ""
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                await MainActor.run {
                    isAuthenticated = false
                    username = ""
                }
                return
            }
            
            if let scopes = httpResponse.value(forHTTPHeaderField: "X-OAuth-Scopes") {
                let scopeList = scopes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let hasRequiredScope = scopeList.contains("repo") || scopeList.contains("public_repo")
                
                if !hasRequiredScope {
                    await MainActor.run {
                        isAuthenticated = false
                        username = "Missing 'repo' scope"
                    }
                    return
                }
            }
            
            struct GitHubUser: Codable {
                let login: String
                let name: String?
            }
            
            let user = try JSONDecoder().decode(GitHubUser.self, from: data)
            await MainActor.run {
                username = user.name ?? user.login
                isAuthenticated = true
            }
        } catch {
            await MainActor.run {
                isAuthenticated = false
                username = ""
            }
        }
    }

    private func signOut() {
        githubToken = ""
        username = ""
        isAuthenticated = false
        KeychainManager.shared.githubToken = ""
    }
    
    private func loadTokenFromKeychain() {
        githubToken = KeychainManager.shared.githubToken
    }
    
    private func saveTokenToKeychain() {
        KeychainManager.shared.githubToken = githubToken
    }
}

@available(iOS 26.0, *)
struct CMSConfigView: View {
    @ObservedObject var publishManager: PublishManager
    @State private var isLoading = false
    
    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading configuration...")
                            .foregroundColor(.secondary)
                    }
                }
            } else if let error = publishManager.configLoadError {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                    
                    Button("Retry") {
                        loadConfig()
                    }
                    .buttonStyle(.glass)
                }
            } else if let config = publishManager.cmsConfig {
                Section("Media Settings") {
                    LabeledContent("Media Folder", value: config.mediaFolder)
                    LabeledContent("Public Folder", value: config.publicFolder)
                }
                
                if let collection = config.photoCollection {
                    Section("Photo Collection") {
                        LabeledContent("Name", value: collection.name)
                        LabeledContent("Folder", value: collection.folder)
                        LabeledContent("Path Template", value: collection.path ?? "(none)")
                        LabeledContent("Slug Template", value: collection.slugTemplate ?? "(none)")
                        LabeledContent("Media Location", value: collection.usesMediaInEntry ? "With entry (leaf bundle)" : collection.mediaFolder)
                        LabeledContent("Public Folder", value: collection.publicFolder.isEmpty ? "(relative)" : collection.publicFolder)
                    }
                }
                
                Section {
                    Button("Reload Configuration") {
                        loadConfig()
                    }
                    .buttonStyle(.glass)
                }
            } else {
                Section {
                    Text("Configuration not loaded")
                        .foregroundColor(.secondary)
                    
                    Button("Load Configuration") {
                        loadConfig()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("CMS Configuration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if publishManager.cmsConfig == nil && publishManager.configLoadError == nil {
                loadConfig()
            }
        }
    }
    
    private func loadConfig() {
        isLoading = true
        Task {
            await publishManager.loadCMSConfig()
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

#Preview {
    if #available(iOS 26.0, *) {
        SettingsView()
            .preferredColorScheme(.dark)
    } else {
        Text("Requires iOS 26.0")
    }
}
