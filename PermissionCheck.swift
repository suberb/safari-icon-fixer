import Foundation

func isSafariPermissionError(_ error: Error) -> Bool {
    var current: NSError? = error as NSError
    for _ in 0..<8 {
        guard let e = current else { break }
        if e.domain == NSCocoaErrorDomain && (e.code == 257 || e.code == 513) { return true }
        if e.domain == NSPOSIXErrorDomain && (e.code == 1 || e.code == 13) { return true }
        let description = e.localizedDescription.lowercased()
        if ["operation not permitted", "permission denied", "authorization denied", "not authorized", "brak uprawnień", "nie masz uprawnień"].contains(where: { description.contains($0) }) { return true }
        current = e.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return false
}
