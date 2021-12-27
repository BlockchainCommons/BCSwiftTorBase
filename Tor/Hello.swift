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

func hello() {
    print(LZMA_VERSION_MAJOR)
    print(OPENSSL_VERSION_NUMBER)
    print(EVENT__VERSION)
    print(String(cString: tor_api_get_provider_version()))
}
