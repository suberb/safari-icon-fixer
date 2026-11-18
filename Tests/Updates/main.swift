import Foundation
precondition(ReleaseVersion("v0.3.10")! > ReleaseVersion("0.3.9")!)
precondition(ReleaseVersion("v1.0.0")! > ReleaseVersion("0.99.99")!)
precondition(ReleaseVersion("0.3.2") == ReleaseVersion("v0.3.2"))
for invalid in ["v0.3.2-beta", "0.3", "0.03.2", "0.3.-2", "0.3.2/", "0.3.+2", "0.3.2+5"] { precondition(ReleaseVersion(invalid) == nil) }
let json = #"{"tag_name":"v0.3.10","draft":false,"prerelease":false,"body":"Zmiany","assets":[{"name":"SafariIconFixer-0.3.10-macOS-arm64.zip"}]}"#
let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
precondition(release.version == ReleaseVersion("0.3.10"))
precondition(release.macAsset(architecture: "arm64") != nil)
precondition(release.macAsset(architecture: "x86_64") == nil)
let draft = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.replacingOccurrences(of: "\"draft\":false", with: "\"draft\":true").utf8))
precondition(draft.version == nil)
print("OK: wersje, stabilne wydania, architektura")

let dmgJSON = json.replacingOccurrences(of: ".zip", with: ".dmg")
let dmg = try JSONDecoder().decode(GitHubRelease.self, from: Data(dmgJSON.utf8))
precondition(dmg.macAsset(architecture: "arm64") == "SafariIconFixer-0.3.10-macOS-arm64.dmg")
precondition(dmg.macAsset(architecture: "x86_64") == nil)
precondition(release.macAsset(architecture: "arm64") == "SafariIconFixer-0.3.10-macOS-arm64.zip")
let bothJSON = #"{"tag_name":"v0.3.10","draft":false,"prerelease":false,"assets":[{"name":"SafariIconFixer-0.3.10-macOS-arm64.zip"},{"name":"SafariIconFixer-0.3.10-macOS-arm64.dmg"}]}"#
let both = try JSONDecoder().decode(GitHubRelease.self, from: Data(bothJSON.utf8))
precondition(both.macAsset(architecture: "arm64") == "SafariIconFixer-0.3.10-macOS-arm64.dmg")
precondition(draft.macAsset(architecture: "arm64") == nil)
print("OK: DMG, fallback ZIP, priorytet i architektura")
