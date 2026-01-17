# decap_pub

Minimal photo publishing apps for Decap CMS sites via GitHub.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐
│   iOS App       │     │  Linux GUI      │
│   (SwiftUI)     │     │  (iced/Rust)    │
└────────┬────────┘     └────────┬────────┘
         │                       │
         ▼                       ▼
┌─────────────────────────────────────────┐
│   Shared Backend Library (Rust)         │
│   - GitHub API client                   │
│   - Decap CMS content formatting        │
│   - YAML frontmatter generation         │
└─────────────────────────────────────────┘
```

## Components

### iOS App (`ios/`)

SwiftUI app for iPhone/iPad:
- Gallery grid view of photo library
- Tap to enlarge, long-press for actions
- Settings panel for site configuration
- Source picker for albums/folders

**Requirements:** Xcode 15+, iOS 17+

```bash
open ios/DecapPub/DecapPub.xcodeproj
```

### Linux GUI (`linux-gui/`)

Native Rust GUI using iced:
- Gallery view of configurable image directory
- Recursive folder traversal option
- Same core functionality as iOS app

**Build:**
```bash
cd linux-gui
cargo build --release
```

**Run:**
```bash
cargo run --release
```

### Shared Backend (`backend/`)

Rust library shared between platforms:
- GitHub API client (commits, blobs, trees)
- Content formatting for Decap CMS
- YAML frontmatter generation
- Path generation matching Decap CMS config

For iOS integration, build with UniFFI:
```bash
cd backend
cargo build --release --features uniffi
```

### CLI (`cli/`)

Optional command-line tool for scripting:

```bash
# Configure
decap-pub config --repo owner/repo --token ghp_xxx

# Publish
decap-pub publish photo.jpg --title "My Photo" --tags "travel,nature"
```

## Configuration

All apps use the same configuration structure:

| Setting | Description | Default |
|---------|-------------|---------|
| `site_url` | Site URL | `https://crawfordlong.com` |
| `github_repo` | Repository (owner/repo) | `crawfordlong/crawfordlong-com-2025` |
| `github_branch` | Branch to commit to | `trunk` |
| `content_path` | Path in repo for content | `content/photos` |
| `github_token` | GitHub PAT or OAuth token | (required) |

## How It Works

1. Select photo(s) from gallery
2. App reads image data and EXIF metadata
3. Backend formats content:
   - Generates slug from title
   - Creates directory path: `content/photos/YYYY/MM/DD/HHMM-slug/`
   - Generates `index.md` with YAML frontmatter
4. Backend commits to GitHub:
   - Creates blobs for image and markdown
   - Creates tree with new files
   - Creates commit
   - Updates branch ref
5. Site rebuilds via CI/CD (Cloudflare Pages, Netlify, etc.)

## Development

Build all Rust components:
```bash
cargo build
```

Run tests:
```bash
cargo test
```

## License

MIT
