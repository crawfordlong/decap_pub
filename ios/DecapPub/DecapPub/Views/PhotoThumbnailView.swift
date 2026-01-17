import SwiftUI

struct PhotoThumbnailView: View {
    let photo: PhotoItem
    let isSelected: Bool
    let isSelecting: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = photo.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1, contentMode: .fill)
                    .overlay {
                        ProgressView()
                    }
            }

            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .white)
                    .background(Circle().fill(isSelected ? .white : .black.opacity(0.3)))
                    .padding(6)
            }
        }
        .overlay {
            if isSelected && isSelecting {
                Rectangle()
                    .stroke(Color.blue, lineWidth: 3)
            }
        }
    }
}

#Preview {
    HStack {
        PhotoThumbnailView(
            photo: PhotoItem(id: "1", asset: nil),
            isSelected: false,
            isSelecting: false
        )
        .frame(width: 100, height: 100)

        PhotoThumbnailView(
            photo: PhotoItem(id: "2", asset: nil),
            isSelected: true,
            isSelecting: true
        )
        .frame(width: 100, height: 100)
    }
}
