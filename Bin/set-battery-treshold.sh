#!/usr/bin/env -S bash

# Check if exectly one argument was provided
if [ "$#" -ne 1 ]; then
    echo "Error: Battery level not specified" >&2
    echo "Usage: $0 <number>" >&2
    exit 1
fi

# Check if argument is a number
if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "Error: Battery level must be a number" >&2
    echo "Usage: $0 <number>" >&2
    exit 1
fi

echo "$1" | pkexec tee ~/test
