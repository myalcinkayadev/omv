// Helper for share.sh. Built with swiftc on first use.
//   share airdrop <path...>   opens macOS's AirDrop sheet for the files
// Exits 0 once the AirDrop window closes, non-zero when AirDrop isn't available or the share
// fails. macOS reports a cancelled share as done, so 0 doesn't mean the files were sent.

import AppKit

final class Sharer: NSObject, NSSharingServiceDelegate {
  var status: Int32 = 1

  func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
    status = 0
    finish()
  }

  func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
    status = 1
    finish()
  }

  // Ends app.run(): stop only takes effect after another event, so post one.
  func finish() {
    let app = NSApplication.shared
    app.stop(nil)
    app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
  }
}

let arguments = CommandLine.arguments
guard arguments.count > 2, arguments[1] == "airdrop" else {
  FileHandle.standardError.write("usage: share airdrop <path...>\n".data(using: .utf8)!)
  exit(2)
}
let files = arguments.dropFirst(2).map { URL(fileURLWithPath: $0) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let airdrop = NSSharingService(named: .sendViaAirDrop), airdrop.canPerform(withItems: files) else {
  FileHandle.standardError.write("AirDrop isn't available\n".data(using: .utf8)!)
  exit(1)
}
let sharer = Sharer()
airdrop.delegate = sharer
app.activate(ignoringOtherApps: true)
DispatchQueue.main.async { airdrop.perform(withItems: files) }
app.run()
exit(sharer.status)
