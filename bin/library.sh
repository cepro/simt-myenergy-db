#!/bin/sh

BIN_DIR=`dirname $0`
PROJECT_ROOT=`dirname $BIN_DIR`

SUPA_PROJECT_ID=`grep project_id $PROJECT_ROOT/supabase/config.toml  | sed -e 's/.*= "\(.*\)"/\1/'`

# better would be to define our own network and have supabase use that too.
# there is a WIP PR for that so we can do if that gets merged:
# https://github.com/supabase/cli/pull/1581
#
# for now put timescale on the same network as supabase so it can connect
# to timescale for foreign data wrapper functionality
NETWORK_NAME=supabase_network_$SUPA_PROJECT_ID

