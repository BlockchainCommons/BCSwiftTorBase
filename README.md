# BCSwiftToreBase

Thin Swift wrapper around [Tor](https://github.com/torproject/tor) that has a new system for building a universal XCFramework for use with MacOSX, Mac Catalyst, iOS devices, and the iOS simulator across Intel and Apple Silicon (ARM).

For higher-level functions, see [BCSwiftTor](https://github.com/BlockchainCommons/BCSwiftTor).

## Dependencies

```sh
$ brew install autoconf autogen gsed
```

## Build

```sh
$ git clone https://github.com/blockchaincommons/BCSwiftTorBase.git
$ cd BCSwiftTorBase
$ ./build.sh
```

The resulting framework is `build/TorBase.xcframework`. Add to your project.
