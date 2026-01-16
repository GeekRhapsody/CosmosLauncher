#!/bin/sh
printf '\033c\033]0;%s\a' Cosmos Launcher
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Cosmos Launcher.x86_64" "$@"
