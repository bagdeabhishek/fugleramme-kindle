#!/bin/sh
DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
exec /bin/sh "$DIR/fugleramme.sh" --once
