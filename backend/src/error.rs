//! Error types for the decap_pub library

use thiserror::Error;

/// Result type alias for decap_pub operations
pub type Result<T> = std::result::Result<T, Error>;

/// Errors that can occur during Decap CMS publishing
#[derive(Error, Debug)]
pub enum Error {
    /// GitHub API error
    #[error("GitHub API error: {0}")]
    GitHub(String),

    /// Authentication error
    #[error("Authentication failed: {0}")]
    Auth(String),

    /// Invalid configuration
    #[error("Invalid configuration: {0}")]
    Config(String),

    /// Content formatting error
    #[error("Content formatting error: {0}")]
    Format(String),

    /// Network error
    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),

    /// JSON serialization error
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// YAML serialization error
    #[error("YAML error: {0}")]
    Yaml(#[from] serde_yaml::Error),

    /// I/O error
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
}
