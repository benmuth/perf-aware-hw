#!/bin/bash


set -e
set -u

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <original bin file>"
    exit 1
fi

original_binary_file_name="$1"


zig build -freference-trace && zig-out/bin/sim8086 "sim" "$original_binary_file_name"
