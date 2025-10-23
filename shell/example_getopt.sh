#!/bin/bash

module="all"

if ! GETOPT_ARGS=$(getopt -q -o r:m: --long rpm:,module: -- "$@");then
    echo "Error: Invalid option." >&2
    exit 1
fi
eval set -- "$GETOPT_ARGS"

while [ -n "$1" ]; do
    case "$1" in
        -r|--rpm)
            if [ -z "$2" ]; then
                echo "Error: -m requires a value." >&2
                exit 1
            fi
            echo "will build rpm $2"
            shift 2
            ;;
        -m|--module)
            if [ -z "$2" ]; then
                echo "Error: -m requires a value." >&2
                exit 1
            fi
            module="$2"
            echo "will build module $module"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "unimplemented option"
            exit 1
            ;;
    esac
done
