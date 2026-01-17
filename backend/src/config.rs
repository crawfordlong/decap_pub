//! Site configuration for Decap CMS publishing

use serde::{Deserialize, Serialize};

/// Configuration for a Decap CMS site
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SiteConfig {
    /// Display name for the site
    pub site_name: String,

    /// Site URL (e.g., "https://crawfordlong.com")
    pub site_url: String,

    /// GitHub repository in "owner/repo" format
    pub github_repo: String,

    /// Branch to commit to (e.g., "trunk", "main")
    pub github_branch: String,

    /// Path to content directory (e.g., "content/photos")
    pub content_path: String,

    /// GitHub personal access token or OAuth token
    pub github_token: String,
}

impl SiteConfig {
    /// Create a new site configuration
    pub fn new(
        site_name: impl Into<String>,
        site_url: impl Into<String>,
        github_repo: impl Into<String>,
        github_branch: impl Into<String>,
        content_path: impl Into<String>,
        github_token: impl Into<String>,
    ) -> Self {
        Self {
            site_name: site_name.into(),
            site_url: site_url.into(),
            github_repo: github_repo.into(),
            github_branch: github_branch.into(),
            content_path: content_path.into(),
            github_token: github_token.into(),
        }
    }

    /// Parse repository into owner and repo name
    pub fn repo_parts(&self) -> Option<(&str, &str)> {
        self.github_repo.split_once('/')
    }
}

impl Default for SiteConfig {
    fn default() -> Self {
        Self {
            site_name: "Crawford Long".into(),
            site_url: "https://crawfordlong.com".into(),
            github_repo: "crawfordlong/crawfordlong-com-2025".into(),
            github_branch: "trunk".into(),
            content_path: "content/photos".into(),
            github_token: String::new(),
        }
    }
}
