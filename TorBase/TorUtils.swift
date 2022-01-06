//
//  Hello.swift
//  Tor
//
//  Created by Wolf McNally on 12/26/21.
//

import Foundation
import CLZMA
import COpenSSL
import CLibEvent
import CTor

public enum TorUtils {
    public static let EVENT_LOG_DEBUG: UInt32 = 0
    public static let EVENT_LOG_MSG: UInt32   = 1
    public static let EVENT_LOG_WARN: UInt32  = 2
    public static let EVENT_LOG_ERR: UInt32   = 3
    public static let EVENT_DBG_ALL: UInt32 = 0xffffffff
    public static let EVENT_DBG_NONE: UInt32 = 0

    public static var lzmaVersion: String {
        "\(LZMA_VERSION_MAJOR).\(LZMA_VERSION_MINOR).\(LZMA_VERSION_PATCH)"
    }
    
    public static var openSSLVersion: String {
        OPENSSL_VERSION_TEXT
    }
    
    public static var libEventsVersion: String {
        EVENT__VERSION
    }
    
    public static var torVersion: String {
        String(cString: tor_api_get_provider_version())
    }
    
    public static var dependencyVersions: [String: String] {
        [
            "LZMA": lzmaVersion,
            "OpenSSL": openSSLVersion,
            "LibEvent": libEventsVersion,
            "Tor": torVersion
        ]
    }
    
    public static func runTorMain(arguments: [String]) {
        let argc = Int32(arguments.count)
        withArrayOfCStrings(arguments) { argv in
            var argv = argv
            let cfg = tor_main_configuration_new()
            tor_main_configuration_set_command_line(cfg, argc, &argv)
            tor_run_main(cfg)
            tor_main_configuration_free(cfg)
        }
    }
    
    public static func installTorLogging(minLogPriority: Int32, maxLogPriority: Int32, callback: @escaping @convention(c) (_ logPriority: Int32, _ domain: UInt64, _ msg: Optional<UnsafePointer<Int8>>) -> Void) {
        init_logging(1)
        var list = log_severity_list_t()
        set_log_severity_config(minLogPriority, maxLogPriority, &list)
        add_callback_log(&list, callback)
    }
    
    public static func setEventLogCallback(_ cb: @escaping event_log_cb) {
        event_set_log_callback(cb)
    }
    
    public static func setEventDebugLogging(isEnabled: Bool) {
        event_enable_debug_logging(isEnabled ? EVENT_DBG_ALL : EVENT_DBG_NONE)
    }
}

// https://oleb.net/blog/2016/10/swift-array-of-c-strings/
func withArrayOfCStrings<R>(
    _ args: [String],
    _ body: ([UnsafeMutablePointer<CChar>?]) -> R
) -> R {
    var cStrings = args.map { strdup($0) }
    cStrings.append(nil)
    defer {
        cStrings.forEach { free($0) }
    }
    return body(cStrings)
}
