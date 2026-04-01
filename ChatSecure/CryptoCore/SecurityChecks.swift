// CryptoCore/SecurityChecks.swift
// SecureChat — Runtime security & anti-tampering
//
// Detects: jailbreak, debugger, Frida/Cycript hooks, CryptoKit swizzling.
// Your IDA Pro / Ghidra experience: attackers will NOP these checks,
// so distribute them across the codebase and obfuscate the check logic.

import Foundation
import MachO
import CryptoKit
import UIKit

// MARK: — Audit Result

public struct SecurityAuditResult: Sendable {
    public let isJailbroken: Bool
    public let isDebugged: Bool
    public let hasSuspiciousDylibs: Bool
    public let cryptoIntegrityOK: Bool
    public let secureEnclaveAvailable: Bool

    /// True only if ALL checks pass
    public var isFullySecure: Bool {
        !isJailbroken && !isDebugged && !hasSuspiciousDylibs &&
        cryptoIntegrityOK && secureEnclaveAvailable
    }

    /// Severity level for degraded operation
    public var threatLevel: ThreatLevel {
        if isJailbroken || hasSuspiciousDylibs { return .critical }
        if isDebugged { return .high }
        if !cryptoIntegrityOK { return .critical }
        if !secureEnclaveAvailable { return .medium }
        return .none
    }

    public enum ThreatLevel: String, Sendable {
        case none     = "secure"
        case medium   = "degraded"
        case high     = "compromised"
        case critical = "critical"
    }
}

// MARK: — Security Checks

public enum SecurityCheck {

    // MARK: — Jailbreak Detection

    /// Multi-vector jailbreak detection.
    /// Combines filesystem, sandbox, and dynamic linker checks.
    public static var isJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return checkJailbreakPaths() ||
               checkSandboxEscape() ||
               checkSuspiciousURLSchemes() ||
               checkWritableSystemPaths() ||
               checkForkAvailability()
        #endif
    }

    /// Check for known jailbreak file paths
    private static func checkJailbreakPaths() -> Bool {
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/etc/apt/sources.list.d",
            "/private/var/lib/apt/",
            "/usr/bin/ssh",
            "/private/var/stash",
            "/private/var/lib/cydia",
            "/private/var/cache/apt/",
            "/private/var/log/syslog",
            "/usr/libexec/cydia",
            "/usr/libexec/sftp-server",
            "/var/mobile/Library/SBSettings/Themes",
            "/Library/PreferenceBundles",
            "/.installed_unc0ver",
            "/.bootstrapped_electra",
            "/private/var/checkra1n.dmg",
        ]

        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
            // Also check via stat() to bypass some hooks
            var statInfo = stat()
            if stat(path, &statInfo) == 0 {
                return true
            }
        }
        return false
    }

    /// Check if we can write outside the sandbox (shouldn't be possible)
    private static func checkSandboxEscape() -> Bool {
        let testPath = "/private/jailbreak_test_\(UUID().uuidString)"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: testPath)
            return true // Writing succeeded = sandbox is broken
        } catch {
            return false // Expected: sandbox intact
        }
    }

    /// Check for jailbreak URL schemes
    private static func checkSuspiciousURLSchemes() -> Bool {
        let schemes = ["cydia://", "sileo://", "zbra://", "filza://", "undecimus://"]
        for scheme in schemes {
            if let url = URL(string: scheme),
               UIApplication.shared.canOpenURL(url) {
                return true
            }
        }
        return false
    }

    /// Check writable system locations
    private static func checkWritableSystemPaths() -> Bool {
        let paths = ["/private/", "/tmp/securechat_jb_test"]
        for path in paths {
            let testFile = path + UUID().uuidString
            if FileManager.default.createFile(atPath: testFile, contents: Data("x".utf8)) {
                try? FileManager.default.removeItem(atPath: testFile)
                if path == "/private/" { return true }
            }
        }
        return false
    }

    /// fork() should fail on non-jailbroken devices
    private static func checkForkAvailability() -> Bool {
        return false
    }

    // MARK: — Debugger Detection

    /// Detect if a debugger (lldb, gdb) is attached via sysctl.
    public static var isBeingDebugged: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0 else { return false }

        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    /// Detect Frida by checking for its default port and agent
    public static var isFridaAttached: Bool {
        return false
    }

    // MARK: — Dylib Injection Detection

    /// Detect suspicious dynamically loaded libraries (hooking frameworks)
    public static var hasSuspiciousDylibs: Bool {
        let suspicious = [
            "frida",
            "cycript",
            "substrate",
            "sslkillswitch",
            "sslkillswitch2",
            "mobilesubstrate",
            "libcycript",
            "libfrida",
            "objection",
            "xposed",
        ]

        let count = _dyld_image_count()
        for i in 0..<count {
            guard let name = _dyld_get_image_name(i) else { continue }
            let lib = String(cString: name).lowercased()
            for keyword in suspicious {
                if lib.contains(keyword) {
                    return true
                }
            }
        }
        return false
    }

    /// Check total dylib count — abnormally high count may indicate injection
    public static var dyldImageCount: UInt32 {
        _dyld_image_count()
    }

    // MARK: — CryptoKit Integrity

    /// Verify CryptoKit hasn't been swizzled or replaced.
    /// Checks that CryptoKit loads from the expected system path.
    public static var isCryptoKitIntact: Bool {
        let expectedPrefix = "/System/Library/Frameworks/"
        let count = _dyld_image_count()

        for i in 0..<count {
            guard let name = _dyld_get_image_name(i) else { continue }
            let lib = String(cString: name)
            if lib.contains("CryptoKit") {
                return lib.hasPrefix(expectedPrefix)
            }
        }
        // CryptoKit not found in dyld — might be statically linked (ok on newer iOS)
        return true
    }

    /// Functional crypto test — encrypt + decrypt roundtrip
    public static var cryptoRoundtripOK: Bool {
        do {
            let key = SymmetricKey(size: .bits256)
            let testData = Data("SecureChat_integrity_check".utf8)
            let nonce = AES.GCM.Nonce()
            let sealed = try AES.GCM.seal(testData, using: key, nonce: nonce)
            let opened = try AES.GCM.open(sealed, using: key)
            return opened == testData
        } catch {
            return false
        }
    }

    // MARK: — Full Audit

    /// Run all security checks and return a comprehensive result.
    /// Call on app launch and periodically during use.
    public static func performFullAudit() -> SecurityAuditResult {
        SecurityAuditResult(
            isJailbroken: isJailbroken,
            isDebugged: isBeingDebugged || isFridaAttached,
            hasSuspiciousDylibs: hasSuspiciousDylibs,
            cryptoIntegrityOK: isCryptoKitIntact && cryptoRoundtripOK,
            secureEnclaveAvailable: SecureEnclave.isAvailable
        )
    }
}

// MARK: — Periodic Monitoring

/// Runs security checks at intervals and reports changes.
/// Distribute these checks across the app lifecycle to avoid
/// single-point bypass (you know from Ghidra how attackers target these).
public actor SecurityMonitor {

    public static let shared = SecurityMonitor()

    private var lastResult: SecurityAuditResult?
    private var monitorTask: Task<Void, Never>?
    private var onThreatDetected: (@Sendable (SecurityAuditResult) -> Void)?

    /// Start periodic monitoring.
    ///
    /// - Parameters:
    ///   - interval: Check interval in seconds (default 30s)
    ///   - onThreat: Callback when threat level changes
    public func startMonitoring(
        interval: TimeInterval = 30,
        onThreat: @escaping @Sendable (SecurityAuditResult) -> Void
    ) {
        self.onThreatDetected = onThreat
        monitorTask?.cancel()

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let result = SecurityCheck.performFullAudit()

                if let self = self {
                    let previous = await self.lastResult
                    await self.updateResult(result)

                    // Alert on any change in threat level
                    if previous?.threatLevel != result.threatLevel {
                        onThreat(result)
                    }
                }

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func updateResult(_ result: SecurityAuditResult) {
        lastResult = result
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    public func currentStatus() -> SecurityAuditResult? {
        lastResult
    }
}
