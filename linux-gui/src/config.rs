//! Configuration for the Linux GUI app

use decap_pub::SiteConfig;
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    #[serde(flatten)]
    pub site_config: SiteConfig,
    pub source_path: PathBuf,
    pub recursive: bool,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            site_config: SiteConfig::default(),
            source_path: dirs::picture_dir().unwrap_or_else(|| PathBuf::from("/")),
            recursive: false,
        }
    }
}

fn config_path() -> Option<PathBuf> {
    ProjectDirs::from("com", "decap-pub", "decap-pub-gui")
        .map(|dirs| dirs.config_dir().join("config.toml"))
}

pub fn load_config() -> Result<AppConfig, Box<dyn std::error::Error>> {
    let path = config_path().ok_or("Could not determine config directory")?;

    if !path.exists() {
        return Ok(AppConfig::default());
    }

    let contents = fs::read_to_string(&path)?;
    let config: AppConfig = toml::from_str(&contents)?;

    Ok(config)
}

pub fn save_config(config: &AppConfig) -> Result<(), Box<dyn std::error::Error>> {
    let path = config_path().ok_or("Could not determine config directory")?;

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let contents = toml::to_string_pretty(config)?;
    fs::write(&path, contents)?;

    Ok(())
}
