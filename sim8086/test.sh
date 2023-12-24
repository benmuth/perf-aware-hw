#!/bin/sh

zig build && zig-out/bin/sim8086 listing_0037_single_register_mov listing_0037_single_register_mov.asm && cat output/listing_0037_single_register_mov.asm
