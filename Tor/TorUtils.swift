//
//  Hello.swift
//  Tor
//
//  Created by Wolf McNally on 12/26/21.
//

import Foundation
import lzma
import openssl
import libevent
import ctor

public func dependencyVersionNumbers() -> [String: String] {
    [
        "lzma": "\(LZMA_VERSION_MAJOR).\(LZMA_VERSION_MINOR).\(LZMA_VERSION_PATCH)",
        "openssl": OPENSSL_VERSION_TEXT,
        "libevent": EVENT__VERSION,
        "tor": String(cString: tor_api_get_provider_version())
    ]
}
