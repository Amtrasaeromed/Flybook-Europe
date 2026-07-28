#!/bin/zsh
set -e
cd "$(dirname "$0")"
/usr/bin/xcrun swift run "Flybook Image Studio"
