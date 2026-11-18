import Foundation
import CryptoKit

// Independent cross-check: ensure CI's signing secret matches Info.plist's public key.
// Only the PUBLIC key and public signature are passed to this process.
let args = CommandLine.arguments
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}
guard args.count == 4,
      let key = Data(base64Encoded: args[2]), key.count == 32,
      let signature = Data(base64Encoded: args[3]), signature.count == 64 else {
    fail("Invalid public key or signature format.")
}
let verifier = try Curve25519.Signing.PublicKey(rawRepresentation: key)
let archive = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
guard verifier.isValidSignature(signature, for: archive) else {
    fail("Update signature does not match Info.plist's public key. Publication stopped.")
}
print("OK: update archive signature matches embedded public key.")
