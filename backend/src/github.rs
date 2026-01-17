//! GitHub API client for creating commits

use base64::Engine;
use reqwest::header::{HeaderMap, HeaderValue, ACCEPT, AUTHORIZATION, USER_AGENT};
use serde::{Deserialize, Serialize};

use crate::config::SiteConfig;
use crate::content::{ContentFormatter, PhotoContent};
use crate::error::{Error, Result};

/// GitHub API client
pub struct GitHubClient {
    client: reqwest::Client,
    token: String,
}

#[derive(Debug, Serialize)]
struct CreateBlobRequest {
    content: String,
    encoding: String,
}

#[derive(Debug, Deserialize)]
struct CreateBlobResponse {
    sha: String,
}

#[derive(Debug, Serialize)]
struct TreeEntry {
    path: String,
    mode: String,
    #[serde(rename = "type")]
    entry_type: String,
    sha: String,
}

#[derive(Debug, Serialize)]
struct CreateTreeRequest {
    base_tree: String,
    tree: Vec<TreeEntry>,
}

#[derive(Debug, Deserialize)]
struct CreateTreeResponse {
    sha: String,
}

#[derive(Debug, Serialize)]
struct CreateCommitRequest {
    message: String,
    tree: String,
    parents: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct CreateCommitResponse {
    sha: String,
    html_url: String,
}

#[derive(Debug, Serialize)]
struct UpdateRefRequest {
    sha: String,
    force: bool,
}

#[derive(Debug, Deserialize)]
struct RefResponse {
    object: RefObject,
}

#[derive(Debug, Deserialize)]
struct RefObject {
    sha: String,
}

#[derive(Debug, Deserialize)]
struct CommitResponse {
    sha: String,
    commit: CommitInfo,
}

#[derive(Debug, Deserialize)]
struct CommitInfo {
    tree: TreeRef,
}

#[derive(Debug, Deserialize)]
struct TreeRef {
    sha: String,
}

impl GitHubClient {
    /// Create a new GitHub API client
    pub fn new(token: &str) -> Result<Self> {
        if token.is_empty() {
            return Err(Error::Auth("GitHub token is required".into()));
        }

        let mut headers = HeaderMap::new();
        headers.insert(
            ACCEPT,
            HeaderValue::from_static("application/vnd.github+json"),
        );
        headers.insert(
            "X-GitHub-Api-Version",
            HeaderValue::from_static("2022-11-28"),
        );
        headers.insert(USER_AGENT, HeaderValue::from_static("decap-pub/0.1.0"));

        let client = reqwest::Client::builder()
            .default_headers(headers)
            .build()?;

        Ok(Self {
            client,
            token: token.to_string(),
        })
    }

    /// Create a commit with a new photo
    pub async fn create_photo_commit(
        &self,
        config: &SiteConfig,
        photo: &PhotoContent,
        index_content: &str,
        image_filename: &str,
    ) -> Result<String> {
        let (owner, repo) = config
            .repo_parts()
            .ok_or_else(|| Error::Config("Invalid repository format".into()))?;

        let formatter = ContentFormatter::new(config);
        let base_path = formatter.generate_path(photo);

        // 1. Get the current commit SHA for the branch
        let branch_ref = self.get_ref(owner, repo, &config.github_branch).await?;
        let base_commit = self.get_commit(owner, repo, &branch_ref).await?;

        // 2. Create blobs for index.md and the image
        let index_blob = self
            .create_blob(owner, repo, index_content.as_bytes(), false)
            .await?;
        let image_blob = self
            .create_blob(owner, repo, &photo.image_data, true)
            .await?;

        // 3. Create a new tree with the files
        let tree_entries = vec![
            TreeEntry {
                path: format!("{}index.md", base_path),
                mode: "100644".into(),
                entry_type: "blob".into(),
                sha: index_blob,
            },
            TreeEntry {
                path: format!("{}{}", base_path, image_filename),
                mode: "100644".into(),
                entry_type: "blob".into(),
                sha: image_blob,
            },
        ];

        let new_tree = self
            .create_tree(owner, repo, &base_commit.tree_sha, tree_entries)
            .await?;

        // 4. Create a commit
        let commit_message = format!("Add photo: {}", photo.title);
        let commit = self
            .create_commit(owner, repo, &commit_message, &new_tree, &branch_ref)
            .await?;

        // 5. Update the branch reference
        self.update_ref(owner, repo, &config.github_branch, &commit.sha)
            .await?;

        Ok(commit.html_url)
    }

    async fn get_ref(&self, owner: &str, repo: &str, branch: &str) -> Result<String> {
        let url = format!(
            "https://api.github.com/repos/{}/{}/git/ref/heads/{}",
            owner, repo, branch
        );

        let response: RefResponse = self
            .client
            .get(&url)
            .header(AUTHORIZATION, format!("Bearer {}", self.token))
            .send()
            .await?
            .error_for_status()
            .map_err(|e| Error::GitHub(e.to_string()))?
            .json()
            .await?;

        Ok(response.object.sha)
    }

    async fn get_commit(&self, owner: &str, repo: &str, sha: &str) -> Result<CommitInfo2> {
        let url = format!(
            "https://api.github.com/repos/{}/{}/git/commits/{}",
            owner, repo, sha
        );

        let response: CommitResponse = self
            .client
            .get(&url)
            .header(AUTHORIZATION, format!("Bearer {}", self.token))
            .send()
            .await?
            .error_for_status()
            .map_err(|e| Error::GitHub(e.to_string()))?
            .json()
            .await?;

        Ok(CommitInfo2 {
            sha: response.sha,
            tree_sha: response.commit.tree.sha,
        })
    }

    async fn create_blob(
        &self,
        owner: &str,
        repo: &str,
        content: &[u8],
        is_binary: bool,
    ) -> Result<String> {
        let url = format!(
            "https://api.github.com/repos/{}/{}/git/blobs",
            owner, repo
        );

        let (content_str, encoding) = if is_binary {
            (
                base64::engine::general_purpose::STANDARD.encode(content),
                "base64",
            )
        } else {
            (String::from_utf8_lossy(content).into_owned(), "utf-8")
        };

        let request = CreateBlobRequest {
            content: content_str,
            encoding: encoding.into(),
        };

        let response: CreateBlobResponse = self
            .client
            .post(&url)
            .header(AUTHORIZATION, format!("Bearer {}", self.token))
            .json(&request)
            .send()
            .await?
            .error_for_status()
            .map_err(|e| Error::GitHub(e.to_string()))?
            .json()
            .await?;

        Ok(response.sha)
    }

    async fn create_tree(
        &self,
        owner: &str,
        repo: &str,
        base_tree: &str,
        entries: Vec<TreeEntry>,
    ) -> Result<String> {
        let url = format!(
            "https://api.github.com/repos/{}/{}/git/trees",
            owner, repo
        );

        let request = CreateTreeRequest {
            base_tree: base_tree.into(),
            tree: entries,
        };

        let response: CreateTreeResponse = self
            .client
            .post(&url)
            .header(AUTHORIZATION, format!("Bearer {}", self.token))
            .json(&request)
            .send()
            .await?
            .error_for_status()
            .map_err(|e| Error::GitHub(e.to_string()))?
            .json()
            .await?;

        Ok(response.sha)
    }

    async fn create_commit(
        &self,
        owner: &str,
        repo: &str,
        message: &str,
        tree_sha: &str,
        parent_sha: &str,
    ) -> Result<CreateCommitResponse> {
        let url = format!(
            "https://api.github.com/repos/{}/{}/git/commits",
            owner, repo
        );

        let request = CreateCommitRequest {
            message: message.into(),
            tree: tree_sha.into(),
            parents: vec![parent_sha.into()],
        };

        let response: CreateCommitResponse = self
            .client
            .post(&url)
            .header(AUTHORIZATION, format!("Bearer {}", self.token))
            .json(&request)
            .send()
            .await?
            .error_for_status()
            .map_err(|e| Error::GitHub(e.to_string()))?
            .json()
            .await?;

        Ok(response)
    }

    async fn update_ref(
        &self,
        owner: &str,
        repo: &str,
        branch: &str,
        sha: &str,
    ) -> Result<()> {
        let url = format!(
            "https://api.github.com/repos/{}/{}/git/refs/heads/{}",
            owner, repo, branch
        );

        let request = UpdateRefRequest {
            sha: sha.into(),
            force: false,
        };

        self.client
            .patch(&url)
            .header(AUTHORIZATION, format!("Bearer {}", self.token))
            .json(&request)
            .send()
            .await?
            .error_for_status()
            .map_err(|e| Error::GitHub(e.to_string()))?;

        Ok(())
    }
}

struct CommitInfo2 {
    sha: String,
    tree_sha: String,
}
