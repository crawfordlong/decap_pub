//! Configuration file handling for the CLI

use decap_pub::SiteConfig;
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Serialize, Deserialize)]
struct ConfigFile {
    site_name: Option<String>,
    site_url: Option<String>,
    github_repo: Option<String>,
    github_branch: Option<String>,
    content_path: Option<String>,
    github_token: Option<String>,
}

fn config_path() -> Option<PathBuf> {
    ProjectDirs::from("com", "decap-pub", "decap-pub").map(|dirs| dirs.config_dir().join("config.toml"))
}

pub fn load_config() -> Result<SiteConfig, Box<dyn std::error::Error>> {
    let path = config_path().ok_or("Could not determine config directory")?;

    if !path.exists() {
        return Ok(SiteConfig::default());
    }

    let contents = fs::read_to_string(&path)?;
    let file: ConfigFile = toml::from_str(&contents)?;

    Ok(SiteConfig {
        site_name: file.site_name.unwrap_or_else(|| "Crawford Long".into()),
        site_url: file.site_url.unwrap_or_else(|| "https://crawfordlong.com".into()),
        github_repo: file.github_repo.unwrap_or_else(|| "crawfordlong/crawfordlong-com-2025".into()),
        github_branch: file.github_branch.unwrap_or_else(|| "trunk".into()),
        content_path: file.content_path.unwrap_or_else(|| "content/photos".into()),
        github_token: file.github_token.unwrap_or_default(),
    })
}

pub fn save_config(config: &SiteConfig) -> Result<(), Box<dyn std::error::Error>> {
    let path = config_path().ok_or("Could not determine config directory")?;

    // Ensure directory exists
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let file = ConfigFile {
        site_name: Some(config.site_name.clone()),
        site_url: Some(config.site_url.clone()),
        github_repo: Some(config.github_repo.clone()),
        github_branch: Some(config.github_branch.clone()),
        content_path: Some(config.content_path.clone()),
        github_token: Some(config.github_token.clone()),
    };

    let contents = toml::to_string_pretty(&file)?;
    fs::write(&path, contents)?;

    Ok(())
}
