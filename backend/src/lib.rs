//! decap_pub - Shared backend library for publishing to Decap CMS via GitHub
//!
//! This library handles:
//! - GitHub API authentication and operations
//! - Content formatting for Decap CMS (YAML frontmatter)
//! - Image upload and commit creation

mod config;
mod content;
mod error;
mod github;

pub use config::SiteConfig;
pub use content::{PhotoContent, ContentFormatter};
pub use error::{Error, Result};
pub use github::GitHubClient;

/// Main entry point for publishing a photo to a Decap CMS site
pub async fn publish_photo(
    config: &SiteConfig,
    photo: PhotoContent,
) -> Result<String> {
    let client = GitHubClient::new(&config.github_token)?;
    let formatter = ContentFormatter::new(config);

    // Format the content for Decap CMS
    let (index_content, image_path) = formatter.format_photo(&photo)?;

    // Create the directory structure and commit
    let commit_url = client
        .create_photo_commit(config, &photo, &index_content, &image_path)
        .await?;

    Ok(commit_url)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_library_compiles() {
        // Basic smoke test
        assert!(true);
    }
}
