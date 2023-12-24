#!/bin/bash

set -e
set -u

# call this script from the command line with an assembled binary file:
# ./assemble_and_compare.sh <source.bin>

# start with bin file
# run it through 8086 disassembler -> asm file
# use nasm to turn it into bin file -> bin file
# compare original and outputted bin files with cmp -> pass or fail

# Check if a file name is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <original bin file>"
    exit 1
fi

# Assign the argument to a variable for readability
original_binary_file_name="$1"
original_binary_file_path="../../../perf-aware/resources/part1/${original_binary_file_name}"
disassembled_output="../../../perf-aware/hw/sim8086/output/${original_binary_file_name}.asm"
reassembled_output="../../../perf-aware/hw/sim8086/output/${original_binary_file_name}"
# assembled_binary_file="./output/${assembly_source_file%.*}.bin"

# the zig program will put the .asm file in "/home/ben/code/perf-aware/hw/sim8086/output/"
zig build && zig-out/bin/sim8086 "$original_binary_file_name" "${original_binary_file_name}.asm" 

# expected_binary_file_name="$2"
# expected_binary_file_path="/home/ben/code/perf-aware/resources/part1/${expected_binary_file_name}"

# Assemble the assembly file into binary
nasm "${disassembled_output}" -o "${reassembled_output}" 2>/dev/null

# Check the assembler command success
if [[ $? -ne 0 ]]; then
    echo "Assembly failed for ${original_binary_file_name}"
    exit 1
fi

# Compare the newly assembled binary file to the expected binary file
cmp -b "${original_binary_file_path}" "${reassembled_output}" 

# Determine the result based on the `cmp` exit code
if [[ $? -eq 0 ]]; then
    echo "The files are identical."
else
    echo "The files are different."
    exit 1
fi
