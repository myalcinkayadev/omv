// The column beside a permission step: what the step turns on, as omv draws it. Each part names
// the app that powers it, ticked once that app is granted, then shows its images, side by side
// and shrunk to fit the column, its keys and a note. A missing image is left out.

import AppKit
import SwiftUI

struct TurnsOn: View {
  let step: SetupStep
  @EnvironmentObject var state: SetupState

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("TURNS ON").font(Look.font(11)).tracking(1.5).foregroundColor(Look.faint)
      ForEach(Array(step.parts.enumerated()), id: \.offset) { _, part in partView(part) }
    }
  }

  func partView(_ part: SetupPart) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if !part.app.isEmpty { Text(part.app).font(Look.font(11, .bold)) }
        Text(part.what).font(Look.font(11)).foregroundColor(Look.faint).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        if let key = part.key, state.progress.grants[key] == .granted || state.progress.ticked.contains(key) {
          Text("✓").font(Look.font(11)).accessibilityLabel("granted")
        }
      }
      let pictures = part.images.compactMap(previewImage)
      if !pictures.isEmpty { picturesView(pictures).accessibilityLabel(part.what) }
      if !part.keys.isEmpty { keysView(part.keys) }
      if let note = part.note {
        Text(note).font(Look.font(11)).foregroundColor(Look.faint).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  static let columnWidth: CGFloat = 370
  static let tallest: CGFloat = 380
  static let gap: CGFloat = 10

  // The images at their own size, or smaller so that together they fit the column's width and
  // none is taller than the tallest a preview may be.
  func picturesView(_ pictures: [(picture: NSImage, size: CGSize)]) -> some View {
    let natural = pictures.map(\.size.width).reduce(0, +)
    let room = TurnsOn.columnWidth - TurnsOn.gap * CGFloat(pictures.count - 1)
    let byWidth = min(1, room / natural)
    let byHeight = min(1, TurnsOn.tallest / (pictures.map(\.size.height).max() ?? 1))
    let scale = min(byWidth, byHeight)
    return HStack(alignment: .top, spacing: TurnsOn.gap) {
      ForEach(Array(pictures.enumerated()), id: \.offset) { _, item in
        Image(nsImage: item.picture).resizable().interpolation(.high)
          .frame(width: item.size.width * scale, height: item.size.height * scale)
      }
    }
  }

  // The images are taken at twice their size, on a Retina screen.
  func previewImage(_ name: String) -> (picture: NSImage, size: CGSize)? {
    guard let path = SetupModel.previewPath(repo: state.repo, image: name),
      let picture = NSImage(contentsOfFile: path),
      let pixels = picture.representations.first else { return nil }
    return (picture, CGSize(width: CGFloat(pixels.pixelsWide) / 2, height: CGFloat(pixels.pixelsHigh) / 2))
  }

  func keysView(_ rows: [SetupKeys]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 12) {
          HStack(spacing: 3) {
            ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
              Text(key).font(Look.font(10)).padding(.horizontal, 5).frame(minWidth: 18).frame(height: 17)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.35)))
            }
          }
          .frame(width: 150, alignment: .leading)
          Text(row.does).font(Look.font(11)).foregroundColor(Look.soft)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }
}
