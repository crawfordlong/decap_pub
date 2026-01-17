import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
                }

                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        resetToDefaults()
                    }
                }
            }
            .navigationTitle("Settings")
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

    private func resetToDefaults() {
        siteEndpoint = "https://crawfordlong.com"
        siteName = "Crawford Long"
        githubRepo = "crawfordlong/crawfordlong-com-2025"
        githubBranch = "trunk"
        contentPath = "content/photos"
    }
}

struct GitHubAuthView: View {
    @AppStorage("githubToken") private var githubToken = ""
    @State private var isAuthenticated = false
    @State private var username = ""

    var body: some View {
        Form {
            if isAuthenticated {
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

                    Button("Sign in with GitHub") {
                        initiateOAuth()
                    }
                }

                Section("Or use a Personal Access Token") {
                    SecureField("GitHub Token", text: $githubToken)
                        .autocapitalization(.none)

                    Button("Verify Token") {
                        verifyToken()
                    }
                    .disabled(githubToken.isEmpty)
                }
            }
        }
        .navigationTitle("GitHub Account")
        .onAppear {
            checkAuthStatus()
        }
    }

    private func checkAuthStatus() {
        // TODO: Verify token with GitHub API
        isAuthenticated = !githubToken.isEmpty
    }

    private func initiateOAuth() {
        // TODO: Implement OAuth flow via ASWebAuthenticationSession
    }

    private func verifyToken() {
        // TODO: Verify token with GitHub API
        isAuthenticated = true
    }

    private func signOut() {
        githubToken = ""
        username = ""
        isAuthenticated = false
    }
}

#Preview {
    SettingsView()
}
