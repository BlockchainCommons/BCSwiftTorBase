#!zsh
set -e # abort if any command fails

MIN_IOS_VERSION=15
MIN_MAC_VERSION=12
PROJ_ROOT=${PWD}
DEPS_ROOT=${PROJ_ROOT}/deps
BUILD_ROOT=${PROJ_ROOT}/build
BUILD_LOG=${PROJ_ROOT}/buildlog.txt
CPU_COUNT=$(sysctl hw.ncpu | awk '{print $2}')

mkdir -p ${BUILD_ROOT}
echo -n > ${BUILD_LOG}

# Terminal colors
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
CYAN=`tput setaf 6`
RESET=`tput sgr0`

progress_section() (
  MESSAGE="=== ${1} ==="
  echo ${MESSAGE}
  echo "${CYAN}${MESSAGE}${RESET}" >&3
)

progress_item() (
  MESSAGE="== ${1} =="
  echo ${MESSAGE}
  echo "${BLUE}${MESSAGE}${RESET}" >&3
)

progress_success() (
  MESSAGE="==== ${1} ===="
  echo ${MESSAGE}
  echo "${GREEN}${MESSAGE}${RESET}" >&3
)

progress_warning() (
  MESSAGE="* ${1} *"
  echo ${MESSAGE}
  echo "${YELLOW}${MESSAGE}${RESET}" >&3
)

progress_error() (
  MESSAGE="** ${1} **"
  echo ${MESSAGE}
  echo "${RED}${MESSAGE}${RESET}" >&3
)

get_dependencies() (
  progress_section "Getting Dependencies"
  git submodule update --init --recursive
)

build_init()
{
  LIB_NAME=$1
  TARGET=$2
  SDK=$3
  BITCODE=$4
  VERSION=$5
  SDK_PATH=`xcrun -sdk ${SDK} --show-sdk-path`
  BUILD_ARCH_DIR=${BUILD_ROOT}/${TARGET}
  PREFIX=${BUILD_ARCH_DIR}/${LIB_NAME}

  mkdir -p ${BUILD_ARCH_DIR}

  export CFLAGS="-O3 -isysroot ${SDK_PATH} -target ${TARGET} ${BITCODE} ${VERSION} -Wall -Wno-overriding-t-option"
  export CXXFLAGS="-O3 -isysroot ${SDK_PATH} -target ${TARGET} ${BITCODE} ${VERSION} -Wall -Wno-overriding-t-option"
  export LDFLAGS="-target ${TARGET} ${BITCODE}"
  export CC="$(xcrun --sdk ${SDK} -f clang)"
  export CXX="$(xcrun --sdk ${SDK} -f clang++)"

  export LIBTOOL=`which glibtool`
  export LIBTOOLIZE=`which glibtoolize`

  progress_item "${LIB_NAME} ${TARGET}"
}

build_xz()
(
  build_init liblzma $@

  pushd ${DEPS_ROOT}/bc-xz

  if [[ ! -f ./configure ]]; then
      ./autogen.sh --no-po4a
  fi

  make distclean 2>/dev/null ||:
  rm -rf "${PREFIX}/"

  ./configure \
    --disable-shared \
    --enable-static \
    --disable-doc \
    --disable-scripts \
    --disable-xz \
    --disable-xzdec \
    --disable-lzmadec \
    --disable-lzmainfo \
    --disable-lzma-links \
    --prefix="${PREFIX}" \
    cross_compiling="yes" \
    ac_cv_func_clock_gettime="no"
  make -j${CPU_COUNT}
  make install
  make distclean

  cp ${PROJ_ROOT}/Modulemaps/CLZMA.modulemap ${PREFIX}/lib/module.modulemap

  popd
)

build_openssl()
(
  build_init openssl $@

  CONF_FILE=${DEPS_ROOT}/openssl/Configurations/20-bc-openssl.conf
  cp bc-openssl.conf ${CONF_FILE}

  pushd ${DEPS_ROOT}/openssl

  make distclean 2>/dev/null ||:
  rm -rf "${PREFIX}/"

  ./Configure \
    --prefix=${PREFIX} \
    bc-${TARGET}

  make depend
  make -j${CPU_COUNT} build_libs
  make install_dev
  make distclean
  rm ${CONF_FILE}

  cp ${PROJ_ROOT}/Modulemaps/COpenSSL.modulemap ${PREFIX}/lib/module.modulemap

  popd
)

build_libevent()
(
  build_init libevent $@

  pushd ${DEPS_ROOT}/libevent

  ./autogen.sh

  make distclean 2>/dev/null ||:
  rm -rf "${PREFIX}/"

  # We need XPC to build libevent, so copy it from the OSX SDK into a temporary directory
  XPC_INCLUDE_DIR=${PREFIX}/libevent-xpc
  mkdir -p "${XPC_INCLUDE_DIR}/xpc"
  cp -f "$(xcrun --sdk macosx --show-sdk-path)/usr/include/xpc/base.h" "${XPC_INCLUDE_DIR}/xpc"

  export CFLAGS="${CFLAGS} -I\"${PREFIX}\" -I\"${DEPS_ROOT}/openssl/include\" -I\"${XPC_INCLUDE_DIR}\""
  export LDFLAGS="${LDFLAGS} -L${PREFIX}"

  # https://github.com/libevent/libevent/issues/1136
  export PKG_CONFIG_PATH="${BUILD_ARCH_DIR}/openssl/lib/pkgconfig"

  ./configure \
    --disable-shared \
    --enable-static \
    --enable-gcc-hardening \
    --prefix=${PREFIX} \
    cross_compiling=yes \
    ac_cv_func_clock_gettime=no
  make -j${CPU_COUNT}
  make install
  make clean
  rm -rf build-aux

  cp ${PROJ_ROOT}/Modulemaps/CLibEvent.modulemap ${PREFIX}/lib/module.modulemap

  popd
)

build_tor()
(
  build_init tor $@

  SRC_ROOT=${DEPS_ROOT}/bc-tor
  pushd ${SRC_ROOT}

  if [[ ! -f ./configure ]]; then
      ./autogen.sh --add-missing
  fi
  make distclean 2>/dev/null ||:
  rm -rf "${PREFIX}/"

  # Disable PT_DENY_ATTACH because it is private API.
  PSEUDO_SYS_INCLUDE_DIR=${PREFIX}/tor-sys
  mkdir -p ${PSEUDO_SYS_INCLUDE_DIR}/sys
  touch ${PSEUDO_SYS_INCLUDE_DIR}/sys/ptrace.h

  TARGET_DIR=${BUILD_ROOT}/${TARGET}

  export CPPFLAGS="${CPPFLAGS} \
    -I${SRC_ROOT}/core \
    -I${DEPS_ROOT}/openssl/include \
    -I${PREFIX} \
    -I${DEPS_ROOT}/libevent/include \
    -I${TARGET_DIR}/libevent \
    -I${TARGET_DIR}/libevent/include \
    -I${TARGET_DIR}/liblzma \
    -I${TARGET_DIR}/liblzma/include \
    -I${PSEUDO_SYS_INCLUDE_DIR} \
    "
  export LDFLAGS="${LDFLAGS} -lz"

  ./configure \
    --enable-restart-debugging \
    --enable-silent-rules \
    --enable-pic \
    --disable-module-dirauth \
    --disable-tool-name-check \
    --disable-unittests \
    --enable-static-openssl \
    --enable-static-libevent \
    --disable-asciidoc \
    --disable-system-torrc \
    --disable-linker-hardening \
    --disable-dependency-tracking \
    --disable-manpage \
    --disable-html-manual \
    --prefix=${PREFIX} \
    --with-libevent-dir=${TARGET_DIR}/libevent \
    --with-openssl-dir=${TARGET_DIR}/openssl \
    --with-zlib-dir=${TARGET_DIR}/liblzma \
    --enable-lzma \
    --enable-zstd=no \
    cross_compiling=yes \
    ac_cv_func__NSGetEnviron=no \
    ac_cv_func_clock_gettime=no \
    ac_cv_func_getentropy=no

  make clean

  declare LIBS=(`make show-libs`)
  echo LIBRARIES: ${LIBS[@]}

  # There seems to be a race condition with the above configure and the later cp.
  # Just sleep a little so the correct file is copied and delete the old one before.
  sleep 2
  rm -f src/lib/cc/orconfig.h
  cp orconfig.h src/lib/cc/

  make -j${CPU_COUNT}

  PREFIX_LIB=${PREFIX}/lib
  mkdir -p ${PREFIX_LIB}

  for LIB in ${LIBS[@]}
  do
      cp $LIB "${PREFIX_LIB}/$(basename $LIB)"
  done

  cp micro-revision.i ${PREFIX_LIB}

  FEATURE_API=feature/api
  LIB_LOG=lib/log
  LIB_CC=lib/cc
  LIB_DEFS=lib/defs
  LIB_TESTSUPPORT=lib/testsupport
  PREFIX_INCLUDE=${PREFIX}/include
  SRC_ROOT_SRC=${SRC_ROOT}/src

  # Main API include
  mkdir -p ${PREFIX_INCLUDE}/${FEATURE_API}
  cp ${SRC_ROOT_SRC}/${FEATURE_API}/tor_api.h ${PREFIX_INCLUDE}/${FEATURE_API}/
  # Internal includes for logging. Unstable and may change.
  cp orconfig.h ${PREFIX_INCLUDE}/
  mkdir -p ${PREFIX_INCLUDE}/${LIB_LOG}
  cp ${SRC_ROOT_SRC}/${LIB_LOG}/log.h ${PREFIX_INCLUDE}/${LIB_LOG}/torlog.h
  mkdir -p ${PREFIX_INCLUDE}/${LIB_CC}
  cp ${SRC_ROOT_SRC}/${LIB_CC}/torint.h ${PREFIX_INCLUDE}/${LIB_CC}/
  cp ${SRC_ROOT_SRC}/${LIB_CC}/compat_compiler.h ${PREFIX_INCLUDE}/${LIB_CC}/
  mkdir -p ${PREFIX_INCLUDE}/${LIB_DEFS}
  cp ${SRC_ROOT_SRC}/${LIB_DEFS}/logging_types.h ${PREFIX_INCLUDE}/${LIB_DEFS}/
  mkdir -p ${PREFIX_INCLUDE}/${LIB_TESTSUPPORT}
  cp ${SRC_ROOT_SRC}/${LIB_TESTSUPPORT}/testsupport.h ${PREFIX_INCLUDE}/${LIB_TESTSUPPORT}/

  make clean
  rm -f src/lib/cc/orconfig.h
  rm -rf ${PSEUDO_SYS_INCLUDE_DIR}

  cp ${PROJ_ROOT}/Modulemaps/CTor.modulemap ${PREFIX}/lib/module.modulemap

  popd
)

build_c_libraries()
(
  progress_section "Building C Libraries"

  #             TARGET                      SDK              BITCODE                 VERSION
  ARM_IOS=(     arm64-apple-ios             iphoneos         -fembed-bitcode         -mios-version-min=${MIN_IOS_VERSION})

  X86_CATALYST=(x86_64-apple-ios-macabi     macosx           -fembed-bitcode         -mmacosx-version-min=${MIN_MAC_VERSION})
  ARM_CATALYST=(arm64-apple-ios-macabi      macosx           -fembed-bitcode         -mmacosx-version-min=${MIN_MAC_VERSION})

  X86_IOS_SIM=( x86_64-apple-ios-simulator  iphonesimulator  -fembed-bitcode-marker  -mios-simulator-version-min=${MIN_IOS_VERSION})
  ARM_IOS_SIM=( arm64-apple-ios-simulator   iphonesimulator  -fembed-bitcode-marker  -mios-simulator-version-min=${MIN_IOS_VERSION})

  X86_MAC=(     x86_64-apple-darwin         macosx           -fembed-bitcode         -mmacosx-version-min=${MIN_MAC_VERSION})
  ARM_MAC=(     arm64-apple-darwin          macosx           -fembed-bitcode         -mmacosx-version-min=${MIN_MAC_VERSION})

  build_xz ${ARM_IOS[@]}
  build_xz ${X86_CATALYST[@]}
  build_xz ${ARM_CATALYST[@]}
  build_xz ${X86_IOS_SIM[@]}
  build_xz ${ARM_IOS_SIM[@]}
  build_xz ${X86_MAC[@]}
  build_xz ${ARM_MAC[@]}

  build_openssl ${ARM_IOS[@]}
  build_openssl ${X86_CATALYST[@]}
  build_openssl ${ARM_CATALYST[@]}
  build_openssl ${X86_IOS_SIM[@]}
  build_openssl ${ARM_IOS_SIM[@]}
  build_openssl ${X86_MAC[@]}
  build_openssl ${ARM_MAC[@]}

  build_libevent ${ARM_IOS[@]}
  build_libevent ${X86_CATALYST[@]}
  build_libevent ${ARM_CATALYST[@]}
  build_libevent ${X86_IOS_SIM[@]}
  build_libevent ${ARM_IOS_SIM[@]}
  build_libevent ${X86_MAC[@]}
  build_libevent ${ARM_MAC[@]}

  build_tor ${ARM_IOS[@]}
  build_tor ${X86_CATALYST[@]}
  build_tor ${ARM_CATALYST[@]}
  build_tor ${X86_IOS_SIM[@]}
  build_tor ${ARM_IOS_SIM[@]}
  build_tor ${X86_MAC[@]}
  build_tor ${ARM_MAC[@]}
)

build_framework()
(
  FRAMEWORK=TorBase
  TARGET=$1
  SDK=$2
  PLATFORM_DIR=$3
  CATALYST=$4
  BITCODE=$5
  VERSION=$6
  CONFIGURATION=Debug

  TARGET_ELEMS=("${(@s/-/)TARGET}")
  ARCHS=${TARGET_ELEMS[1]}

  LIBS_NAMES=(liblzma openssl libevent tor)

  LIBS_PATHS=()
  for e in $LIBS_NAMES; do
    LIBS_PATHS+=\"${BUILD_ROOT}/${TARGET}/${e}/lib\"
  done

  INCLUDE_PATHS=()
  for e in $LIBS_NAMES; do
    INCLUDE_PATHS+=\"${BUILD_ROOT}/${TARGET}/${e}/include\"
  done

  FRAMEWORK_ROOT=${PROJ_ROOT}/${FRAMEWORK}

  PROJECT=${PROJ_ROOT}/TorBase.xcodeproj
  SCHEME=TorBase
  DEST_DIR=${BUILD_ROOT}/${TARGET}
  FRAMEWORK_DIR_NAME=${FRAMEWORK}.framework
  rm -rf ${DEST_DIR}/${FRAMEWORK_DIR_NAME}

  LIBS=(\
    -llzma \
    -lcrypto \
    -lssl \
    -levent \
    -levent_pthreads \
    -levent_openssl \
    -levent_core \
    -levent_extra \
    -ltor \
  )

  ARGS=(\
    -project ${PROJECT} \
    -scheme ${SCHEME} \
    -configuration ${CONFIGURATION} \
    -sdk ${SDK} \
    ${VERSION} \
    LIBRARY_SEARCH_PATHS="${LIBS_PATHS}" \
    HEADER_SEARCH_PATHS="${INCLUDE_PATHS}" \
    ONLY_ACTIVE_ARCH=YES \
    ARCHS=${ARCHS} \
    SKIP_INSTALL=NO \
    BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
    SUPPORTS_MACCATALYST=${CATALYST} \
    BITCODE_GENERATION_MODE=${BITCODE} \
    CODE_SIGN_IDENTITY= \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=NO \
    OTHER_LDFLAGS="${LIBS}" \
    )

  # (
  #   printf $'\n'
  #   printf " <%s> " $@
  #   printf $'\n'
  #   printf " <%s> " $LIBS_NAMES
  #   printf $'\n'
  #   printf " <%s> " $ARGS
  #   printf $'\n'
  #   printf $'\n'
  # ) >&3
  #   exit 0

  progress_item "${FRAMEWORK} ${TARGET}"

  # This has the complete swift module information
  xcodebuild clean build ${ARGS[@]}

  # This has the complete Bitcode information
  ARCHIVE_PATH=${DEST_DIR}/${FRAMEWORK}.xcarchive
  rm -rf ${ARCHIVE_PATH}
  xcodebuild archive -archivePath ${ARCHIVE_PATH} ${ARGS[@]}

  BUILD_DIR=`xcodebuild ${ARGS[@]} -showBuildSettings | grep -o '\<BUILD_DIR = .*' | cut -d ' ' -f 3`

  if [[ ${PLATFORM_DIR} == NONE ]]
  then
    FRAMEWORK_SOURCE_DIR=${BUILD_DIR}/${CONFIGURATION}
  else
    FRAMEWORK_SOURCE_DIR=${BUILD_DIR}/${CONFIGURATION}-${PLATFORM_DIR}
  fi

  cp -R ${FRAMEWORK_SOURCE_DIR}/${FRAMEWORK_DIR_NAME} ${DEST_DIR}/

  xcodebuild clean ${ARGS[@]}

  # Copy the binary from the framework in the archive to the main framework so we have correct Swift module information
  # **and** complete Bitcode information.
  cp ${ARCHIVE_PATH}/Products/Library/Frameworks/${FRAMEWORK_DIR_NAME}/${FRAMEWORK} ${DEST_DIR}/${FRAMEWORK_DIR_NAME}/

  # Delete the archive, we no longer need it.
  rm -rf ${ARCHIVE_PATH}

  #echo diff -rq "${FRAMEWORK_SOURCE_DIR}/${FRAMEWORK_DIR_NAME}" "${DEST_DIR}/${FRAMEWORK_DIR_NAME}"
)

build_frameworks()
(
  progress_section "Building Frameworks"

  #              TARGET                      SDK              PLATFORM_DIR     CATALYST  BITCODE  VERSION
  ARM_IOS=(      arm64-apple-ios             iphoneos         iphoneos         NO        bitcode  IPHONEOS_DEPLOYMENT_TARGET=${MIN_IOS_VERSION})
  X86_CATALYST=( x86_64-apple-ios-macabi     macosx           maccatalyst      YES       bitcode  MACOSX_DEPLOYMENT_TARGET=${MIN_MAC_VERSION})
  ARM_CATALYST=( arm64-apple-ios-macabi      macosx           maccatalyst      YES       bitcode  MACOSX_DEPLOYMENT_TARGET=${MIN_MAC_VERSION})
  X86_IOS_SIM=(  x86_64-apple-ios-simulator  iphonesimulator  iphonesimulator  NO        marker   IPHONEOS_DEPLOYMENT_TARGET=${MIN_IOS_VERSION})
  ARM_IOS_SIM=(  arm64-apple-ios-simulator   iphonesimulator  iphonesimulator  NO        marker   IPHONEOS_DEPLOYMENT_TARGET=${MIN_IOS_VERSION})
  X86_MAC=(      x86_64-apple-darwin         macosx           NONE             NO        bitcode  MACOSX_DEPLOYMENT_TARGET=${MIN_MAC_VERSION})
  ARM_MAC=(      arm64-apple-darwin          macosx           NONE             NO        bitcode  MACOSX_DEPLOYMENT_TARGET=${MIN_MAC_VERSION})

  build_framework ${ARM_IOS[@]}
  build_framework ${X86_CATALYST[@]}
  build_framework ${ARM_CATALYST[@]}
  build_framework ${X86_IOS_SIM[@]}
  build_framework ${ARM_IOS_SIM[@]}
  build_framework ${X86_MAC[@]}
  build_framework ${ARM_MAC[@]}
)

build_fat_framework_variant()
(
  FRAMEWORK=$1
  PLATFORM=$2
  FRAMEWORK_DIR_NAME=${FRAMEWORK}.framework
  PLATFORMFRAMEWORK=${PLATFORM}/${FRAMEWORK_DIR_NAME}
  FRAMEWORK1DIR=${BUILD_ROOT}/arm64-${PLATFORMFRAMEWORK}
  FRAMEWORK2DIR=${BUILD_ROOT}/x86_64-${PLATFORMFRAMEWORK}
  DESTDIR=${BUILD_ROOT}/${PLATFORMFRAMEWORK}

  progress_item "${FRAMEWORK} ${PLATFORM}"

  TRAPZERR() { }
  set +e; FRAMEWORK_LINK=`readlink ${FRAMEWORK1DIR}/${FRAMEWORK}`; set -e
  TRAPZERR() { return $(( 128 + $1 )) }
  ARCHIVE_PATH=${FRAMEWORK_LINK:-$FRAMEWORK}

  FRAMEWORK1ARCHIVE=${FRAMEWORK1DIR}/${ARCHIVE_PATH}
  FRAMEWORK2ARCHIVE=${FRAMEWORK2DIR}/${ARCHIVE_PATH}
  DESTARCHIVE=${DESTDIR}/${ARCHIVE_PATH}

  mkdir -p ${BUILD_ROOT}/${PLATFORM}
  rm -rf ${DESTDIR}
  cp -R ${FRAMEWORK1DIR} ${DESTDIR}
  rm -f ${DESTARCHIVE}
  lipo -create ${FRAMEWORK1ARCHIVE} ${FRAMEWORK2ARCHIVE} -output ${DESTARCHIVE}

  if [[ -d ${FRAMEWORK2DIR}/Modules ]]
  then
    # Merge the Modules directories
    cp -R ${FRAMEWORK2DIR}/Modules/* ${DESTDIR}/Modules
  fi
)

build_fat_framework()
(
  FRAMEWORK=$1
  build_fat_framework_variant ${FRAMEWORK} apple-ios-macabi
  build_fat_framework_variant ${FRAMEWORK} apple-ios-simulator
  build_fat_framework_variant ${FRAMEWORK} apple-darwin
)

build_fat_frameworks()
(
  progress_section "Building Fat Frameworks"

  build_fat_framework TorBase
)

build_xcframework()
(
  FRAMEWORK_NAME=$1

  PLATFORM_FRAMEWORK_NAME=${FRAMEWORK_NAME}.framework
  XC_FRAMEWORK_NAME=${FRAMEWORK_NAME}.xcframework
  XC_FRAMEWORK_PATH=${BUILD_ROOT}/${XC_FRAMEWORK_NAME}

  progress_item "${XC_FRAMEWORK_NAME}"

  rm -rf ${XC_FRAMEWORK_PATH}
  xcodebuild -create-xcframework \
  -framework ${BUILD_ROOT}/arm64-apple-ios/${PLATFORM_FRAMEWORK_NAME} \
  -framework ${BUILD_ROOT}/apple-darwin/${PLATFORM_FRAMEWORK_NAME} \
  -framework ${BUILD_ROOT}/apple-ios-macabi/${PLATFORM_FRAMEWORK_NAME} \
  -framework ${BUILD_ROOT}/apple-ios-simulator/${PLATFORM_FRAMEWORK_NAME} \
  -output ${XC_FRAMEWORK_PATH}

  # As of September 22, 2020, the step above is broken:
  # it creates unusable XCFrameworks; missing files like Modules/CryptoBase.swiftmodule/Project/x86_64-apple-ios-simulator.swiftsourceinfo
  # The frameworks we started with were fine. So we're going to brute-force replace the frameworks in the XCFramework with the originials.

  rm -rf ${XC_FRAMEWORK_PATH}/ios-arm64/${PLATFORM_FRAMEWORK_NAME}
  cp -R ${BUILD_ROOT}/arm64-apple-ios/${PLATFORM_FRAMEWORK_NAME} ${XC_FRAMEWORK_PATH}/ios-arm64/

  rm -rf ${XC_FRAMEWORK_PATH}/ios-arm64_x86_64-maccatalyst/${PLATFORM_FRAMEWORK_NAME}
  cp -R ${BUILD_ROOT}/apple-ios-macabi/${PLATFORM_FRAMEWORK_NAME} ${XC_FRAMEWORK_PATH}/ios-arm64_x86_64-maccatalyst/

  rm -rf ${XC_FRAMEWORK_PATH}/ios-arm64_x86_64-simulator/${PLATFORM_FRAMEWORK_NAME}
  cp -R ${BUILD_ROOT}/apple-ios-simulator/${PLATFORM_FRAMEWORK_NAME} ${XC_FRAMEWORK_PATH}/ios-arm64_x86_64-simulator/

  rm -rf ${XC_FRAMEWORK_PATH}/macos-arm64_x86_64/${PLATFORM_FRAMEWORK_NAME}
  cp -R ${BUILD_ROOT}/apple-darwin/${PLATFORM_FRAMEWORK_NAME} ${XC_FRAMEWORK_PATH}/macos-arm64_x86_64/
)

build_xcframeworks()
(
  progress_section "Building XCFramework"

  build_xcframework TorBase
)

build_all()
(
  CONTEXT=subshell

  get_dependencies
  build_c_libraries
  build_frameworks
  build_fat_frameworks
  build_xcframeworks
)

CONTEXT=top

TRAPZERR() {
  if [[ ${CONTEXT} == "top" ]]
  then
    progress_error "Build error."
    echo "Log tail:" >&3
    tail -n 10 ${BUILD_LOG} >&3
  fi

  return $(( 128 + $1 ))
}

TRAPINT() {
  if [[ ${CONTEXT} == "top" ]]
  then
    progress_error "Build stopped."
  fi

  return $(( 128 + $1 ))
}

(
  exec 3>/dev/tty
  build_all
  progress_success "Done!"
) >>&| ${BUILD_LOG}
