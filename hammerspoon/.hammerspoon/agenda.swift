// Helper for agenda.sh, built with swiftc on first use into a small app bundle.
//   agenda <file>   writes today's events to <file>, one per line:
//                   start<TAB>end<TAB>all-day (1 or 0)<TAB>title, with times in Unix seconds,
//                   or the single line "denied" when Calendar access is refused.
// macOS asks the app that reads calendars for permission, and needs that app to say why.
// Hammerspoon says nothing about calendars, so this runs as its own app, started by open.
// Cancelled events and ones you declined are left out.

import AppKit
import EventKit

func accessGranted() -> Bool {
  let status = EKEventStore.authorizationStatus(for: .event)
  if #available(macOS 14.0, *) {
    if status == .fullAccess { return true }
  } else if status == .authorized {
    return true
  }
  guard status == .notDetermined else { return false }
  let answered = DispatchSemaphore(value: 0)
  var allowed = false
  let finish: (Bool, Error?) -> Void = { granted, _ in
    allowed = granted
    answered.signal()
  }
  if #available(macOS 14.0, *) {
    EKEventStore().requestFullAccessToEvents(completion: finish)
  } else {
    EKEventStore().requestAccess(to: .event, completion: finish)
  }
  answered.wait()
  return allowed
}

func oneLine(_ text: String) -> String {
  text.components(separatedBy: CharacterSet(charactersIn: "\t\r\n")).joined(separator: " ")
}

func declined(_ event: EKEvent) -> Bool {
  event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
}

func todaysEvents() -> String {
  // A new store, because one made before access was granted sees no calendars.
  let store = EKEventStore()
  let start = Calendar.current.startOfDay(for: Date())
  let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
  let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
  return store.events(matching: predicate)
    .filter { $0.status != .canceled && !declined($0) }
    .map { event in
      let times = "\(Int(event.startDate.timeIntervalSince1970))\t\(Int(event.endDate.timeIntervalSince1970))"
      return "\(times)\t\(event.isAllDay ? 1 : 0)\t\(oneLine(event.title ?? ""))\n"
    }
    .joined()
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
  FileHandle.standardError.write("usage: agenda <file>\n".data(using: .utf8)!)
  exit(2)
}
// Checks in with the system as an app with no Dock icon, as open expects.
NSApplication.shared.setActivationPolicy(.prohibited)
let text = accessGranted() ? todaysEvents() : "denied\n"
do {
  try text.write(to: URL(fileURLWithPath: arguments[1]), atomically: true, encoding: .utf8)
} catch {
  exit(1)
}
exit(0)
