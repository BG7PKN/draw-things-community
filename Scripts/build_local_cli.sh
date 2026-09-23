#!/usr/bin/env bash

set -euo pipefail

GIT_ROOT=$(git rev-parse --show-toplevel)

cd "$GIT_ROOT"

DESTINATION="${DRAWTHINGS_CLI_INSTALL_DIR:-$HOME/.local/bin}"
SDK_VERSION="${DRAWTHINGS_CLI_SDK_VERSION:-26.0}"

# Do not drop the -Xlinker flags. Package.swift declares macOS 13 as the minimum, so SwiftPM
# records minos *and* sdk as 13.0 in LC_BUILD_VERSION. Metal's runtime shader compiler picks its
# default MSL language version from that recorded sdk, and 13.0 yields a pre-Metal-4 version:
# ccv's int8 kernels then fail to compile because <MetalPerformancePrimitives/...> collapses
# under __HAVE_TENSOR__. Raising only the recorded sdk fixes that without raising the deployment
# target, which is why 13.0 stays the first value.
swift build -c release --product draw-things-cli \
  -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$SDK_VERSION"

mkdir -p "$DESTINATION"
install -m 755 .build/release/draw-things-cli "$DESTINATION/draw-things-cli"

case ":$PATH:" in
  *":$DESTINATION:"*) ;;
  *) echo "warning: $DESTINATION is not on PATH, so the installed binary will not run." >&2 ;;
esac

echo "Installed: $DESTINATION/draw-things-cli"
"$DESTINATION/draw-things-cli" --version
