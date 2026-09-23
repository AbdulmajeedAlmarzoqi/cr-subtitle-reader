import Foundation
import Security

enum CodeSignatureError: LocalizedError {
    case unreadable(OSStatus)
    case badRequirement
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let status): return "The downloaded app's signature could not be read (\(status))."
        case .badRequirement: return "The signature requirement could not be built."
        case .invalid(let message): return "The downloaded app is not signed by the CR Subtitle Reader team: \(message)"
        }
    }
}

/// Code-signature checks. Releases are signed with the project's Developer ID certificate and
/// notarized by Apple, so an update must carry a valid Developer ID signature from the same team
/// before it is allowed to replace the running app.
enum CodeSignature {
    static func verifyDeveloperID(appAt url: URL, bundleIdentifier: String, teamIdentifier: String) throws {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else {
            throw CodeSignatureError.unreadable(createStatus)
        }
        // Developer ID: Apple's intermediate CA (1.2.840.113635.100.6.2.6), a Developer ID
        // Application leaf (1.2.840.113635.100.6.1.13), and this team's identifier.
        let text = "anchor apple generic and identifier \"\(bundleIdentifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else {
            throw CodeSignatureError.badRequirement
        }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSCheckNestedCode) | UInt32(kSecCSStrictValidate))
        var cfError: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, req, &cfError)
        guard status == errSecSuccess else {
            let message = cfError?.takeRetainedValue().localizedDescription
                ?? (SecCopyErrorMessageString(status, nil) as String?)
                ?? "status \(status)"
            throw CodeSignatureError.invalid(message)
        }
    }

    /// Team identifier of the running app's own signature; nil when unsigned or ad hoc.
    static var currentTeamIdentifier: String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let me = selfCode else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(me, [], &staticCode) == errSecSuccess, let code = staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
