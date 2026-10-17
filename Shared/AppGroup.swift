import Foundation
import Darwin

/// Finds the shared folder that the app and the widget both read.
/// Sideloading tools (SideStore / AltStore / Sideloadly) often rename the app group,
/// so we check what the installed app was really given before falling back.
enum AppGroup {
    static let defaultID = "group.com.aelshal.todo"

    static let containerURL: URL = {
        for id in candidateIDs() {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url
            }
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    /// True when the app and widget share storage (widget will stay in sync).
    static var isShared: Bool {
        containerURL != FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func candidateIDs() -> [String] {
        var ids: [String] = []
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            ids += alt
        }
        ids += entitlementGroups()
        ids.append(defaultID)
        return ids
    }

    /// Reads the app-group entitlement the binary was actually signed with.
    private static func entitlementGroups() -> [String] {
        typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
        typealias CopyFn = @convention(c) (AnyObject, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<AnyObject>?
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let createSym = dlsym(rtldDefault, "SecTaskCreateFromSelf"),
              let copySym = dlsym(rtldDefault, "SecTaskCopyValueForEntitlement") else { return [] }
        let create = unsafeBitCast(createSym, to: CreateFn.self)
        let copy = unsafeBitCast(copySym, to: CopyFn.self)
        guard let task = create(nil)?.takeRetainedValue() else { return [] }
        let value = copy(task, "com.apple.security.application-groups" as CFString, nil)?.takeRetainedValue()
        return value as? [String] ?? []
    }
}
