#!/bin/bash
# Full Build Script for Unix (macOS/Linux)
# Usage: ./scripts/build.sh [--release] [--skip-codegen] [--skip-rust] [--skip-flutter]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/rust"
FLUTTER_DIR="$PROJECT_ROOT/flutter"

RELEASE_MODE=false
SKIP_CODEGEN=false
SKIP_RUST=false
SKIP_FLUTTER=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --release|-r)
            RELEASE_MODE=true
            shift
            ;;
        --skip-codegen)
            SKIP_CODEGEN=true
            shift
            ;;
        --skip-rust)
            SKIP_RUST=true
            shift
            ;;
        --skip-flutter)
            SKIP_FLUTTER=true
            shift
            ;;
    esac
done

BUILD_TYPE=$([ "$RELEASE_MODE" = true ] && echo "release" || echo "debug")

echo -e "\033[36m=== Latera Full Build ===\033[0m"
echo -e "\033[90mBuild type: $BUILD_TYPE\033[0m"
echo -e "\033[90mProject root: $PROJECT_ROOT\033[0m"

# Step 1: Codegen
if [ "$SKIP_CODEGEN" = false ]; then
    echo -e "\n\033[33m[1/3] Running FRB codegen...\033[0m"
    "$SCRIPT_DIR/codegen.sh"
    if [ $? -ne 0 ]; then
        echo -e "\033[31mERROR: Codegen failed!\033[0m"
        exit 1
    fi
else
    echo -e "\n\033[90m[1/3] Skipping codegen...\033[0m"
fi

# Step 2: Build Rust
if [ "$SKIP_RUST" = false ]; then
    echo -e "\n\033[33m[2/3] Building Rust library...\033[0m"
    pushd "$RUST_DIR" > /dev/null
    
    CARGO_ARGS="build"
    if [ "$RELEASE_MODE" = true ]; then
        CARGO_ARGS="$CARGO_ARGS --release"
    fi
    
    cargo $CARGO_ARGS
    if [ $? -ne 0 ]; then
        echo -e "\033[31mERROR: Rust build failed!\033[0m"
        popd > /dev/null
        exit 1
    fi
    popd > /dev/null
else
    echo -e "\n\033[90m[2/3] Skipping Rust build...\033[0m"
fi

# Step 3: Build Flutter
if [ "$SKIP_FLUTTER" = false ]; then
    echo -e "\n\033[33m[3/3] Building Flutter app...\033[0m"
    pushd "$FLUTTER_DIR" > /dev/null
    
    FLUTTER_ARGS="build"
    if [ "$(uname)" = "Darwin" ]; then
        FLUTTER_ARGS="$FLUTTER_ARGS macos"
    else
        FLUTTER_ARGS="$FLUTTER_ARGS linux"
    fi
    
    if [ "$RELEASE_MODE" = true ]; then
        FLUTTER_ARGS="$FLUTTER_ARGS --release"
    else
        FLUTTER_ARGS="$FLUTTER_ARGS --debug"
    fi
    
    flutter $FLUTTER_ARGS
    if [ $? -ne 0 ]; then
        echo -e "\033[31mERROR: Flutter build failed!\033[0m"
        popd > /dev/null
        exit 1
    fi
    popd > /dev/null
else
    echo -e "\n\033[90m[3/3] Skipping Flutter build...\033[0m"
fi

echo -e "\n\033[32m=== Build completed successfully! ===\033[0m"

if [ "$SKIP_FLUTTER" = false ]; then
    if [ "$(uname)" = "Darwin" ]; then
        OUTPUT_PATH="$FLUTTER_DIR/build/macos/Build/Products/$BUILD_TYPE"
    else
        OUTPUT_PATH="$FLUTTER_DIR/build/linux/x64/$BUILD_TYPE/bundle"
    fi
    echo -e "\033[36mOutput: $OUTPUT_PATH\033[0m"
fi
