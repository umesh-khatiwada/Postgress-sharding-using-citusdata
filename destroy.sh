#!/usr/bin/env bash
# Root shortcut for destroying all Citus cluster services
exec "$(dirname "$0")/common/destroy-cluster.sh" "$@"
