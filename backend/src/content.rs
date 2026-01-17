//! Content formatting for Decap CMS

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::config::SiteConfig;
use crate::error::{Error, Result};

/// Photo content to be published
#[derive(Debug, Clone)]
pub struct PhotoContent {
    /// Original filename
    pub filename: String,

    /// Photo title
    pub title: String,

    /// Optional caption/description
    pub caption: Option<String>,

    /// Tags for the photo
    pub tags: Vec<String>,

    /// Creation date of the photo
    pub date: DateTime<Utc>,

    /// Raw image data (JPEG/PNG bytes)
    pub image_data: Vec<u8>,

    /// MIME type (e.g., "image/jpeg")
    pub mime_type: String,
}

/// Frontmatter structure matching Decap CMS config
#[derive(Debug, Serialize, Deserialize)]
struct PhotoFrontmatter {
    title: String,
    date: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    tags: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    caption: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    image: Option<String>,
}

/// Formats content for Decap CMS
pub struct ContentFormatter<'a> {
    config: &'a SiteConfig,
}

impl<'a> ContentFormatter<'a> {
    /// Create a new content formatter
    pub fn new(config: &'a SiteConfig) -> Self {
        Self { config }
    }

    /// Format a photo for Decap CMS
    ///
    /// Returns (index.md content, image filename)
    pub fn format_photo(&self, photo: &PhotoContent) -> Result<(String, String)> {
        // Determine image extension from MIME type
        let extension = match photo.mime_type.as_str() {
            "image/jpeg" | "image/jpg" => "jpg",
            "image/png" => "png",
            "image/heic" => "heic",
            "image/webp" => "webp",
            _ => return Err(Error::Format(format!("Unsupported image type: {}", photo.mime_type))),
        };

        let image_filename = format!("image.{}", extension);

        // Create frontmatter
        let frontmatter = PhotoFrontmatter {
            title: photo.title.clone(),
            date: photo.date.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string(),
            tags: photo.tags.clone(),
            caption: photo.caption.clone(),
            image: Some(image_filename.clone()),
        };

        // Serialize to YAML
        let yaml = serde_yaml::to_string(&frontmatter)?;

        // Build the index.md content
        let content = format!("---\n{}---\n", yaml);

        Ok((content, image_filename))
    }

    /// Generate the directory path for a photo based on Decap CMS config
    ///
    /// Format: content/photos/YYYY/MM/DD/HHMM-slug/
    pub fn generate_path(&self, photo: &PhotoContent) -> String {
        let slug = self.slugify(&photo.title);
        let date = photo.date;

        format!(
            "{}/{:04}/{:02}/{:02}/{:02}{:02}-{}/",
            self.config.content_path,
            date.format("%Y"),
            date.format("%m"),
            date.format("%d"),
            date.format("%H"),
            date.format("%M"),
            slug
        )
    }

    /// Convert a title to a URL-safe slug
    fn slugify(&self, title: &str) -> String {
        title
            .to_lowercase()
            .chars()
            .map(|c| {
                if c.is_alphanumeric() {
                    c
                } else if c.is_whitespace() || c == '-' || c == '_' {
                    '-'
                } else {
                    '-'
                }
            })
            .collect::<String>()
            .split('-')
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join("-")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_slugify() {
        let config = SiteConfig::default();
        let formatter = ContentFormatter::new(&config);

        assert_eq!(formatter.slugify("Hello World"), "hello-world");
        assert_eq!(formatter.slugify("Test  Photo!"), "test-photo-");
        assert_eq!(formatter.slugify("café"), "caf-");
    }
}
