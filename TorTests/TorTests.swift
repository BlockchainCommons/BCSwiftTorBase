//
//  TorTests.swift
//  TorTests
//
//  Created by Wolf McNally on 12/26/21.
//

import XCTest
import Tor

class TorTests: XCTestCase {
    func testVersionNumbers() throws {
        print(dependencyVersionNumbers())
    }
}
