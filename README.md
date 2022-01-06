# BCSwiftWally

Thin Swift wrapper around [LibWally](https://github.com/ElementsProject/libwally-core), a collection of useful primitives for cryptocurrency wallets.

This was originally fork of [LibWally Swift](https://github.com/blockchain/libwally-swift), but since has greatly diverged. It has a new build system for building a universal XCFramework for use with MacOSX, Mac Catalyst, iOS devices, and the iOS simulator across Intel and Apple Silicon (ARM).

For higher-level functions and more, see [BCSwiftFoundation](https://github.com/BlockchainCommons/BCSwiftFoundation).

## Dependencies

```sh
$ brew install autoconf autogen gsed
```

## Build

```sh
$ git clone https://github.com/blockchaincommons/BCSwiftWally.git
$ cd BCSwiftWally
$ ./build.sh
```

The resulting framework is `build/BCWally.xcframework`. Add to your project.
