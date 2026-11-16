// The helper that docks beside System Settings while a permission step is open: the apps to
// drag into its list, with their live state. It follows the window and hides when it's gone.

import AppKit
import SwiftUI

final class HelperController {
  private var panel: NSPanel?
  private var timer: Timer?
  private let size = CGSize(width: 300, height: 380)

  func show(_ step: SetupStep, state: SetupState) {
    hide()
    let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
    panel.title = "omv Setup"
    panel.level = .floating
    panel.backgroundColor = .black
    let content = NSHostingView(rootView: HelperView(step: step, close: { [weak self] in self?.back() }).environmentObject(state))
    // Without this the hosting view grows the panel to its content's ideal size.
    content.sizingOptions = []
    panel.contentView = content
    self.panel = panel
    follow()
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.follow() }
  }

  func hide() {
    timer?.invalidate()
    timer = nil
    panel?.orderOut(nil)
    panel = nil
  }

  private func back() {
    hide()
    NSApp.activate(ignoringOtherApps: true)
  }

  // System Settings' frontmost window, from the window list (top-left origin).
  private func settingsFrame() -> CGRect? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in windows where (window[kCGWindowOwnerName as String] as? String) == "System Settings"
      && (window[kCGWindowLayer as String] as? Int) == 0 {
      if let bounds = window[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: bounds) {
        return rect
      }
    }
    return nil
  }

  private func follow() {
    guard let panel, let screen = NSScreen.main else { return }
    let height = NSScreen.screens.first?.frame.height ?? screen.frame.height
    let screenTopLeft = CGRect(x: screen.frame.minX, y: height - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
    guard let frame = SetupModel.helperFrame(settings: settingsFrame(), screen: screenTopLeft, size: size) else {
      panel.orderOut(nil)
      return
    }
    // AppKit counts from the bottom of the main screen.
    panel.setFrame(NSRect(x: frame.minX, y: height - frame.minY - frame.height, width: frame.width, height: frame.height), display: true)
    panel.orderFront(nil)
  }
}

struct HelperView: View {
  let step: SetupStep
  let close: () -> Void
  @EnvironmentObject var state: SetupState

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(step.title).font(Look.font(13, .bold))
      Text("Drag each app into the list in System Settings, then turn its switch on.")
        .font(Look.font(12)).foregroundColor(Look.soft).fixedSize(horizontal: false, vertical: true)
      ForEach(step.permissions, id: \.key) { permission in
        AppRow(permission: permission)
      }
      Spacer()
      Button(action: close) {
        Text("Back to omv Setup").font(Look.font(12)).frame(maxWidth: .infinity).frame(height: 44)
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Look.line))
      }
      .buttonStyle(.plain)
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Look.ground)
    .foregroundColor(.white)
  }
}

// One app to drag: its real icon, its name, and its state or a box to tick.
struct AppRow: View {
  let permission: SetupPermission
  @EnvironmentObject var state: SetupState

  var body: some View {
    let granted = state.progress.isGranted(permission)
    HStack(spacing: 12) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: permission.appPath))
        .resizable().frame(width: 40, height: 40)
        .onDrag { NSItemProvider(object: URL(fileURLWithPath: permission.appPath) as NSURL) }
        .accessibilityLabel("Drag \(permission.app) into the list")
      VStack(alignment: .leading, spacing: 4) {
        Text(permission.app).font(Look.font(12)).lineLimit(1)
        if permission.checkable {
          Text(granted ? "✓ granted" : "◌ waiting · drag me").font(Look.font(11)).foregroundColor(granted ? .white : Look.faint)
        } else {
          Toggle("I turned it on", isOn: Binding(
            get: { state.progress.ticked.contains(permission.key) },
            set: { on in
              if on { state.progress.ticked.insert(permission.key) } else { state.progress.ticked.remove(permission.key) }
            }))
            .toggleStyle(.checkbox).font(Look.font(11))
        }
      }
      Spacer()
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .overlay(RoundedRectangle(cornerRadius: 10)
      .stroke(granted ? Color.white : Color(white: 0.35), style: StrokeStyle(lineWidth: 1, dash: granted ? [] : [4])))
  }
}
