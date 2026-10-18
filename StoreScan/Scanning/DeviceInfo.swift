import Foundation
#if canImport(UIKit)
    import UIKit
#endif

enum DeviceInfo {
    /// The specific hardware identifier (e.g. "iPhone15,3"), not the
    /// generic "iPhone" UIDevice.current.model gives. Read via uname(),
    /// the standard technique since UIDevice has no public API for it.
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce(into: "") { partialResult, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partialResult.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }

    static var osVersion: String {
        #if canImport(UIKit)
            return UIDevice.current.systemVersion
        #else
            return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
}
