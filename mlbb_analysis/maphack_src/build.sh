#!/bin/bash
# Build maphack.dylib for iOS ARM64
# Run this on macOS with Xcode installed

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
OUT=maphack.dylib

clang \
  -arch arm64 \
  -isysroot $SDK \
  -miphoneos-version-min=14.0 \
  -fobjc-arc \
  -dynamiclib \
  -framework UIKit \
  -framework Foundation \
  -o $OUT \
  maphack.m

echo "Built: $OUT"
