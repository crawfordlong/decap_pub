//! decap-pub CLI - Publish photos to Decap CMS from the command line

use clap::{Parser, Subcommand};
use colored::Colorize;
use decap_pub::{PhotoContent, SiteConfig};
use std::path::PathBuf;

mod config;

#[derive(Parser)]
#[command(name = "decap-pub")]
#[command(about = "Publish photos to Decap CMS sites via GitHub")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Publish a photo to the configured site
    Publish {
        /// Path to the image file
        #[arg(required = true)]
        image: PathBuf,

        /// Title for the photo
        #[arg(short, long)]
        title: Option<String>,

        /// Caption/description
        #[arg(short, long)]
        caption: Option<String>,

        /// Tags (comma-separated)
        #[arg(long)]
        tags: Option<String>,
    },

    /// Configure the site settings
    Config {
        /// Site URL
        #[arg(long)]
        site_url: Option<String>,

        /// GitHub repository (owner/repo)
        #[arg(long)]
        repo: Option<String>,

        /// Branch name
        #[arg(long)]
        branch: Option<String>,

        /// Content path in repository
        #[arg(long)]
        content_path: Option<String>,

        /// GitHub token (will prompt if not provided)
        #[arg(long)]
        token: Option<String>,

        /// Show current configuration
        #[arg(long)]
        show: bool,
    },

    /// List recent publications
    List {
        /// Number of items to show
        #[arg(short, long, default_value = "10")]
        limit: usize,
    },
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    let result = match cli.command {
        Commands::Publish {
            image,
            title,
            caption,
            tags,
        } => publish(image, title, caption, tags).await,

        Commands::Config {
            site_url,
            repo,
            branch,
            content_path,
            token,
            show,
        } => {
            if show {
                show_config().await
            } else {
                update_config(site_url, repo, branch, content_path, token).await
            }
        }

        Commands::List { limit } => list_recent(limit).await,
    };

    if let Err(e) = result {
        eprintln!("{} {}", "Error:".red().bold(), e);
        std::process::exit(1);
    }
}

async fn publish(
    image_path: PathBuf,
    title: Option<String>,
    caption: Option<String>,
    tags: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    // Load config
    let site_config = config::load_config()?;

    if site_config.github_token.is_empty() {
        return Err("No GitHub token configured. Run `decap-pub config --token <token>` first.".into());
    }

    // Read image file
    let image_data = tokio::fs::read(&image_path).await?;

    // Determine MIME type from extension
    let mime_type = match image_path.extension().and_then(|e| e.to_str()) {
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("png") => "image/png",
        Some("heic") => "image/heic",
        Some("webp") => "image/webp",
        _ => return Err("Unsupported image format".into()),
    };

    // Generate title from filename if not provided
    let title = title.unwrap_or_else(|| {
        image_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Untitled")
            .to_string()
    });

    let tags: Vec<String> = tags
        .map(|t| t.split(',').map(|s| s.trim().to_string()).collect())
        .unwrap_or_default();

    let photo = PhotoContent {
        filename: image_path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("image")
            .to_string(),
        title: title.clone(),
        caption,
        tags,
        date: chrono::Utc::now(),
        image_data,
        mime_type: mime_type.to_string(),
    };

    println!(
        "{} {} to {}...",
        "Publishing".green().bold(),
        title,
        site_config.site_name
    );

    let commit_url = decap_pub::publish_photo(&site_config, photo).await?;

    println!("{} {}", "Published!".green().bold(), commit_url);

    Ok(())
}

async fn show_config() -> Result<(), Box<dyn std::error::Error>> {
    let config = config::load_config()?;

    println!("{}", "Current Configuration:".bold());
    println!("  Site Name:    {}", config.site_name);
    println!("  Site URL:     {}", config.site_url);
    println!("  Repository:   {}", config.github_repo);
    println!("  Branch:       {}", config.github_branch);
    println!("  Content Path: {}", config.content_path);
    println!(
        "  Token:        {}",
        if config.github_token.is_empty() {
            "(not set)".red().to_string()
        } else {
            "(configured)".green().to_string()
        }
    );

    Ok(())
}

async fn update_config(
    site_url: Option<String>,
    repo: Option<String>,
    branch: Option<String>,
    content_path: Option<String>,
    token: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut config = config::load_config().unwrap_or_default();

    if let Some(url) = site_url {
        config.site_url = url;
    }
    if let Some(r) = repo {
        config.github_repo = r;
    }
    if let Some(b) = branch {
        config.github_branch = b;
    }
    if let Some(p) = content_path {
        config.content_path = p;
    }
    if let Some(t) = token {
        config.github_token = t;
    }

    config::save_config(&config)?;

    println!("{}", "Configuration saved!".green().bold());

    Ok(())
}

async fn list_recent(_limit: usize) -> Result<(), Box<dyn std::error::Error>> {
    // TODO: Implement listing recent commits to the content path
    println!("{}", "List command not yet implemented".yellow());
    Ok(())
}
