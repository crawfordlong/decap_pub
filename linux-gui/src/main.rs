//! decap-pub-gui - Linux GUI for publishing photos to Decap CMS
//!
//! A minimal gallery-style application that mirrors the iOS app functionality.

use iced::widget::{button, column, container, image, row, scrollable, text, Space};
use iced::{executor, Application, Command, Element, Length, Settings, Theme};
use std::path::PathBuf;

mod config;
mod gallery;

fn main() -> iced::Result {
    DecapPubGui::run(Settings {
        window: iced::window::Settings {
            size: iced::Size::new(1024.0, 768.0),
            min_size: Some(iced::Size::new(400.0, 300.0)),
            ..Default::default()
        },
        ..Default::default()
    })
}

#[derive(Debug, Clone)]
pub enum Message {
    // Navigation
    OpenSettings,
    CloseSettings,
    OpenSourcePicker,
    CloseSourcePicker,

    // Photo actions
    PhotoSelected(usize),
    PhotoLongPress(usize),
    TogglePhotoSelection(usize),
    ClearSelection,
    SendSelected,

    // Settings
    SiteUrlChanged(String),
    RepoChanged(String),
    BranchChanged(String),
    ContentPathChanged(String),
    TokenChanged(String),
    SaveSettings,

    // Source
    SourcePathChanged(String),
    BrowseForFolder,
    FolderSelected(Option<PathBuf>),
    ToggleRecursive(bool),
    RefreshGallery,

    // Gallery
    PhotosLoaded(Vec<gallery::PhotoEntry>),
    ThumbnailLoaded(usize, iced::widget::image::Handle),

    // Upload
    UploadStarted,
    UploadProgress(usize, usize),
    UploadComplete(Result<String, String>),
}

struct DecapPubGui {
    // View state
    current_view: View,
    selected_photo: Option<usize>,
    selected_photos: std::collections::HashSet<usize>,
    is_selecting: bool,

    // Data
    photos: Vec<gallery::PhotoEntry>,
    thumbnails: std::collections::HashMap<usize, iced::widget::image::Handle>,

    // Config
    config: config::AppConfig,

    // Source settings
    source_path: PathBuf,
    recursive: bool,

    // Status
    status_message: Option<String>,
    is_loading: bool,
}

#[derive(Debug, Clone, PartialEq)]
enum View {
    Gallery,
    PhotoDetail(usize),
    Settings,
    SourcePicker,
}

impl Application for DecapPubGui {
    type Executor = executor::Default;
    type Message = Message;
    type Theme = Theme;
    type Flags = ();

    fn new(_flags: ()) -> (Self, Command<Message>) {
        let config = config::load_config().unwrap_or_default();
        let source_path = config.source_path.clone();

        (
            Self {
                current_view: View::Gallery,
                selected_photo: None,
                selected_photos: std::collections::HashSet::new(),
                is_selecting: false,
                photos: Vec::new(),
                thumbnails: std::collections::HashMap::new(),
                config,
                source_path,
                recursive: false,
                status_message: None,
                is_loading: true,
            },
            Command::perform(async {}, |_| Message::RefreshGallery),
        )
    }

    fn title(&self) -> String {
        String::from("Decap Pub")
    }

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::OpenSettings => {
                self.current_view = View::Settings;
                Command::none()
            }
            Message::CloseSettings => {
                self.current_view = View::Gallery;
                Command::none()
            }
            Message::OpenSourcePicker => {
                self.current_view = View::SourcePicker;
                Command::none()
            }
            Message::CloseSourcePicker => {
                self.current_view = View::Gallery;
                Command::none()
            }
            Message::PhotoSelected(idx) => {
                if self.is_selecting {
                    self.toggle_selection(idx);
                } else {
                    self.current_view = View::PhotoDetail(idx);
                }
                Command::none()
            }
            Message::PhotoLongPress(idx) => {
                self.is_selecting = true;
                self.selected_photos.insert(idx);
                Command::none()
            }
            Message::TogglePhotoSelection(idx) => {
                self.toggle_selection(idx);
                Command::none()
            }
            Message::ClearSelection => {
                self.is_selecting = false;
                self.selected_photos.clear();
                Command::none()
            }
            Message::SendSelected => {
                // TODO: Implement send
                self.status_message = Some("Sending...".into());
                Command::none()
            }
            Message::BrowseForFolder => Command::perform(
                async {
                    rfd::AsyncFileDialog::new()
                        .set_directory("/")
                        .pick_folder()
                        .await
                        .map(|h| h.path().to_path_buf())
                },
                Message::FolderSelected,
            ),
            Message::FolderSelected(path) => {
                if let Some(p) = path {
                    self.source_path = p;
                    self.config.source_path = self.source_path.clone();
                    return Command::perform(async {}, |_| Message::RefreshGallery);
                }
                Command::none()
            }
            Message::ToggleRecursive(val) => {
                self.recursive = val;
                Command::perform(async {}, |_| Message::RefreshGallery)
            }
            Message::RefreshGallery => {
                let path = self.source_path.clone();
                let recursive = self.recursive;
                self.is_loading = true;
                Command::perform(
                    async move { gallery::load_photos(&path, recursive).await },
                    Message::PhotosLoaded,
                )
            }
            Message::PhotosLoaded(photos) => {
                self.photos = photos;
                self.is_loading = false;
                self.thumbnails.clear();
                // Queue thumbnail loading
                let commands: Vec<_> = self
                    .photos
                    .iter()
                    .enumerate()
                    .map(|(idx, photo)| {
                        let path = photo.path.clone();
                        Command::perform(
                            async move { gallery::load_thumbnail(&path).await },
                            move |handle| Message::ThumbnailLoaded(idx, handle),
                        )
                    })
                    .collect();
                Command::batch(commands)
            }
            Message::ThumbnailLoaded(idx, handle) => {
                self.thumbnails.insert(idx, handle);
                Command::none()
            }
            Message::SiteUrlChanged(url) => {
                self.config.site_config.site_url = url;
                Command::none()
            }
            Message::RepoChanged(repo) => {
                self.config.site_config.github_repo = repo;
                Command::none()
            }
            Message::BranchChanged(branch) => {
                self.config.site_config.github_branch = branch;
                Command::none()
            }
            Message::ContentPathChanged(path) => {
                self.config.site_config.content_path = path;
                Command::none()
            }
            Message::TokenChanged(token) => {
                self.config.site_config.github_token = token;
                Command::none()
            }
            Message::SaveSettings => {
                let _ = config::save_config(&self.config);
                self.current_view = View::Gallery;
                Command::none()
            }
            Message::SourcePathChanged(path) => {
                self.source_path = PathBuf::from(path);
                Command::none()
            }
            _ => Command::none(),
        }
    }

    fn view(&self) -> Element<Message> {
        match &self.current_view {
            View::Gallery => self.view_gallery(),
            View::PhotoDetail(idx) => self.view_photo_detail(*idx),
            View::Settings => self.view_settings(),
            View::SourcePicker => self.view_source_picker(),
        }
    }

    fn theme(&self) -> Theme {
        Theme::Dark
    }
}

impl DecapPubGui {
    fn toggle_selection(&mut self, idx: usize) {
        if self.selected_photos.contains(&idx) {
            self.selected_photos.remove(&idx);
        } else {
            self.selected_photos.insert(idx);
        }
    }

    fn view_gallery(&self) -> Element<Message> {
        let toolbar = row![
            button("...").on_press(Message::OpenSourcePicker),
            Space::with_width(Length::Fill),
            text(format!("{} photos", self.photos.len())),
            Space::with_width(Length::Fill),
            button("⚙").on_press(Message::OpenSettings),
        ]
        .spacing(10)
        .padding(10);

        let grid = if self.is_loading {
            container(text("Loading...")).center_x(Length::Fill).center_y(Length::Fill).into()
        } else if self.photos.is_empty() {
            container(text("No photos found")).center_x(Length::Fill).center_y(Length::Fill).into()
        } else {
            let photos_per_row = 4;
            let rows: Vec<Element<Message>> = self
                .photos
                .chunks(photos_per_row)
                .enumerate()
                .map(|(row_idx, chunk)| {
                    let row_items: Vec<Element<Message>> = chunk
                        .iter()
                        .enumerate()
                        .map(|(col_idx, _photo)| {
                            let idx = row_idx * photos_per_row + col_idx;
                            let is_selected = self.selected_photos.contains(&idx);

                            let thumb: Element<Message> =
                                if let Some(handle) = self.thumbnails.get(&idx) {
                                    image(handle.clone())
                                        .width(150)
                                        .height(150)
                                        .into()
                                } else {
                                    container(text("..."))
                                        .width(150)
                                        .height(150)
                                        .center_x(Length::Fill)
                                        .center_y(Length::Fill)
                                        .into()
                                };

                            let mut thumb_button = button(thumb).on_press(Message::PhotoSelected(idx));

                            if is_selected {
                                thumb_button = thumb_button.style(iced::widget::button::primary);
                            }

                            thumb_button.into()
                        })
                        .collect();

                    row(row_items).spacing(4).into()
                })
                .collect();

            scrollable(column(rows).spacing(4)).into()
        };

        let mut content = column![toolbar, grid].spacing(0);

        if self.is_selecting {
            let selection_bar = row![
                button("Cancel").on_press(Message::ClearSelection),
                Space::with_width(Length::Fill),
                text(format!("{} selected", self.selected_photos.len())),
                Space::with_width(Length::Fill),
                button("Send").on_press(Message::SendSelected),
            ]
            .spacing(10)
            .padding(10);
            content = content.push(selection_bar);
        }

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }

    fn view_photo_detail(&self, idx: usize) -> Element<Message> {
        let back_button = button("← Back").on_press(Message::CloseSettings);

        let photo_view = if let Some(handle) = self.thumbnails.get(&idx) {
            image(handle.clone())
                .width(Length::Fill)
                .height(Length::Fill)
                .into()
        } else {
            text("Loading...").into()
        };

        let photo_info = if let Some(photo) = self.photos.get(idx) {
            column![
                text(&photo.filename).size(18),
                text(format!("Path: {}", photo.path.display())).size(12),
            ]
            .spacing(4)
        } else {
            column![text("Photo not found")]
        };

        column![back_button, photo_view, photo_info]
            .spacing(10)
            .padding(10)
            .into()
    }

    fn view_settings(&self) -> Element<Message> {
        let header = row![
            text("Settings").size(24),
            Space::with_width(Length::Fill),
            button("Done").on_press(Message::SaveSettings),
        ];

        let site_settings = column![
            text("Publication Endpoint").size(16),
            iced::widget::text_input("Site URL", &self.config.site_config.site_url)
                .on_input(Message::SiteUrlChanged),
            text("GitHub Repository").size(16),
            iced::widget::text_input("owner/repo", &self.config.site_config.github_repo)
                .on_input(Message::RepoChanged),
            iced::widget::text_input("Branch", &self.config.site_config.github_branch)
                .on_input(Message::BranchChanged),
            iced::widget::text_input("Content path", &self.config.site_config.content_path)
                .on_input(Message::ContentPathChanged),
            text("GitHub Token").size(16),
            iced::widget::text_input("Token", &self.config.site_config.github_token)
                .on_input(Message::TokenChanged)
                .secure(true),
        ]
        .spacing(8);

        container(column![header, site_settings].spacing(20).padding(20))
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }

    fn view_source_picker(&self) -> Element<Message> {
        let header = row![
            text("Choose Source").size(24),
            Space::with_width(Length::Fill),
            button("Cancel").on_press(Message::CloseSourcePicker),
        ];

        let current_path = column![
            text("Current folder:").size(14),
            text(self.source_path.display().to_string()).size(12),
            row![
                button("Browse...").on_press(Message::BrowseForFolder),
                iced::widget::checkbox("Include subfolders", self.recursive)
                    .on_toggle(Message::ToggleRecursive),
            ]
            .spacing(10),
        ]
        .spacing(8);

        container(column![header, current_path].spacing(20).padding(20))
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
    }
}
