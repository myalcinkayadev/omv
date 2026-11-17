// One app in a permission step: its real icon and name, then how it's granted.

import AppKit
import SwiftUI

// One app: its real icon and name, then how it's granted. Drag and tick rows drag as a whole,
// so any part of the card can go into System Settings' list; ask rows have Continue, which
// brings up macOS's prompt.
struct AppRow: View {
  let permission: SetupPermission
  @EnvironmentObject var state: SetupState

  var body: some View {
    let granted = state.progress.isGranted(permission)
    let card = HStack(spacing: 12) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: permission.appPath))
        .resizable().frame(width: 40, height: 40)
        .accessibilityLabel(permission.way == .ask ? permission.app : "Drag \(permission.app) into the list")
      VStack(alignment: .leading, spacing: 4) {
        Text(permission.app).font(Look.font(12)).lineLimit(1)
        Text(permission.role).font(Look.font(11)).foregroundColor(Look.faint).fixedSize(horizontal: false, vertical: true)
        status(granted)
      }
      Spacer()
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .contentShape(Rectangle())
    .overlay(RoundedRectangle(cornerRadius: 10)
      .stroke(granted ? Color.white : Color(white: 0.35), style: StrokeStyle(lineWidth: 1, dash: granted ? [] : [4])))
    if permission.way == .ask {
      card
    } else {
      card
        .onDrag { NSItemProvider(object: URL(fileURLWithPath: permission.appPath) as NSURL) }
    }
  }

  @ViewBuilder func status(_ granted: Bool) -> some View {
    switch permission.way {
    case .drag where state.progress.grants[permission.key] == .notRunning:
      VStack(alignment: .leading, spacing: 6) {
        Text("✗ not running").font(Look.font(11)).foregroundColor(Look.soft)
        Button { DispatchQueue.global().async { SetupChecks.openAeroSpace() } } label: {
          Text("Open \(permission.app)").font(Look.font(11, .bold)).padding(.horizontal, 10).frame(height: 24)
            .background(Color.white).foregroundColor(.black).cornerRadius(6)
        }
        .buttonStyle(.plain)
      }
    case .drag:
      Text(granted ? "✓ granted" : "◌ waiting · drag me").font(Look.font(11)).foregroundColor(granted ? .white : Look.faint)
    case .tick:
      Toggle("I turned it on", isOn: Binding(
        get: { state.progress.ticked.contains(permission.key) },
        set: { on in
          if on { state.progress.ticked.insert(permission.key) } else { state.progress.ticked.remove(permission.key) }
        }))
        .toggleStyle(.checkbox).font(Look.font(11))
    case .ask:
      if granted {
        Text("✓ granted").font(Look.font(11))
      } else if state.progress.grants[permission.key] == .denied {
        Text("✗ off · switch it on in System Settings").font(Look.font(11)).foregroundColor(Look.soft)
      } else if let problem = state.problems[permission.key] {
        Text("✗ " + problem).font(Look.font(11)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
      } else if state.progress.asking.contains(permission.key) {
        Text("◌ answer macOS's prompt").font(Look.font(11)).foregroundColor(Look.faint)
      } else {
        Button { state.ask(permission) } label: {
          Text(SetupModel.askButton).font(Look.font(11, .bold)).padding(.horizontal, 10).frame(height: 24)
            .background(Color.white).foregroundColor(.black).cornerRadius(6)
        }
        .buttonStyle(.plain)
      }
    }
  }
}
