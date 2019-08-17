#!/bin/bash
set -Eeuo pipefail

redis-server --daemonize yes;
mongod -smallfiles -nojournal --fork --logpath /var/log/mongodb.log;
exec "$@"
