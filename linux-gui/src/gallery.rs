//! Gallery loading and thumbnail generation

use iced::widget::image::Handle;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

#[derive(Debug, Clone)]
pub struct PhotoEntry {
    pub path: PathBuf,
    pub filename: String,
}

/// Load photos from a directory
pub async fn load_photos(path: &Path, recursive: bool) -> Vec<PhotoEntry> {
    let mut photos = Vec::new();

    let walker = if recursive {
        WalkDir::new(path).follow_links(true)
    } else {
        WalkDir::new(path).max_depth(1).follow_links(true)
    };

    for entry in walker.into_iter().filter_map(|e| e.ok()) {
        let path = entry.path();

        if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
            let ext_lower = ext.to_lowercase();
            if matches!(
                ext_lower.as_str(),
                "jpg" | "jpeg" | "png" | "webp" | "heic" | "gif"
            ) {
                photos.push(PhotoEntry {
                    path: path.to_path_buf(),
                    filename: path
                        .file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("unknown")
                        .to_string(),
                });
            }
        }
    }

    // Sort by filename (could also sort by date)
    photos.sort_by(|a, b| a.filename.cmp(&b.filename));

    photos
}

/// Load and resize a thumbnail for a photo
pub async fn load_thumbnail(path: &Path) -> Handle {
    // Try to load and resize the image
    match tokio::task::spawn_blocking({
        let path = path.to_path_buf();
        move || load_thumbnail_sync(&path)
    })
    .await
    {
        Ok(Some(handle)) => handle,
        _ => {
            // Return a placeholder on error
            Handle::from_rgba(1, 1, vec![128, 128, 128, 255])
        }
    }
}

fn load_thumbnail_sync(path: &Path) -> Option<Handle> {
    let img = image::open(path).ok()?;

    // Resize to thumbnail size (150x150 max, maintaining aspect ratio)
    let thumb = img.thumbnail(150, 150);

    // Convert to RGBA
    let rgba = thumb.to_rgba8();
    let (width, height) = rgba.dimensions();

    Some(Handle::from_rgba(
        width,
        height,
        rgba.into_raw(),
    ))
}
