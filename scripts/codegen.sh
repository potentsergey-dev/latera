#!/bin/bash
# FRB Codegen Script for Unix (macOS/Linux)
# Usage: ./scripts/codegen.sh [--watch]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/rust"
FLUTTER_DIR="$PROJECT_ROOT/flutter"
WATCH_MODE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --watch|-w)
            WATCH_MODE=true
            shift
            ;;
    esac
done

echo -e "\033[36m=== Latera FRB Codegen ===\033[0m"
echo -e "\033[90mProject root: $PROJECT_ROOT\033[0m"

# Check if flutter_rust_bridge_codegen is installed
echo -e "\n\033[33mChecking flutter_rust_bridge_codegen...\033[0m"
if ! command -v flutter_rust_bridge_codegen &> /dev/null; then
    echo -e "\033[31mERROR: flutter_rust_bridge_codegen not found!\033[0m"
    echo -e "\033[33mInstall with: cargo install flutter_rust_bridge_codegen\033[0m"
    exit 1
fi
VERSION=$(flutter_rust_bridge_codegen --version 2>/dev/null || echo "unknown")
echo -e "\033[32mFound: flutter_rust_bridge_codegen $VERSION\033[0m"

# Check if Flutter dependencies are installed
echo -e "\n\033[33mChecking Flutter dependencies...\033[0m"
pushd "$FLUTTER_DIR" > /dev/null
if [ ! -f "pubspec.lock" ]; then
    echo -e "\033[33mRunning flutter pub get...\033[0m"
    flutter pub get
    if [ $? -ne 0 ]; then
        echo -e "\033[31mERROR: flutter pub get failed!\033[0m"
        popd > /dev/null
        exit 1
    fi
fi
popd > /dev/null

# Run codegen
echo -e "\n\033[33mRunning FRB codegen...\033[0m"
pushd "$RUST_DIR" > /dev/null

CODEGEN_ARGS=(
    "generate"
    "--rust-input" "crate::api"
    "--rust-root" "."
    "--dart-output" "../flutter/lib/infrastructure/rust/generated"
    "--rust-output" "src/frb_generated.rs"
    "--no-add-mod-to-lib"
)

if [ "$WATCH_MODE" = true ]; then
    CODEGEN_ARGS+=("--watch")
    echo -e "\033[36mWatch mode enabled - will regenerate on changes...\033[0m"
fi

flutter_rust_bridge_codegen "${CODEGEN_ARGS[@]}"

if [ $? -ne 0 ]; then
    echo -e "\n\033[31mERROR: Codegen failed!\033[0m"
    popd > /dev/null
    exit 1
fi

popd > /dev/null

echo -e "\n\033[32m=== Codegen completed successfully! ===\033[0m"
echo -e "\033[36mGenerated files:\033[0m"
echo -e "\033[90m  - Rust:  $RUST_DIR/src/frb_generated.rs\033[0m"
echo -e "\033[90m  - Dart:  $FLUTTER_DIR/lib/infrastructure/rust/generated/\033[0m"
