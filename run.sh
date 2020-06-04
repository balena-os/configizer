#!/usr/bin/env bash

# This oneiner does the following:
# * takes UUIDs from the 'batch' file
# * in parallel runs the update logic on them, with parallelism defined by the '-P' setting
# * if the device was already handled correctly based on the log, its UUID is skipped
# * connect to the device with balena ssh, pipe in the task script, and
#   save the log with the UUID prepended
stdbuf -oL xargs -I{} -P 10 /bin/sh -c "grep -a -q '{} : DONE' config.log 2>/dev/null || (cat config.sh | balena ssh {} | sed 's/^/{} : /' | tee -a config.log)" < "batch"
