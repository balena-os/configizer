#!/usr/bin/env bash

# This oneiner does the following:
# * takes UUIDs from the 'batch' file
# * in parallel runs the update logic on them, with parallelism defined by the '-P' setting
# * if the device was already handled correctly based on the log, its UUID is skipped
# * connect to the device with balena ssh, pipe in the task script, and
#   save the log with the UUID prepended
cat ./batch | \
	stdbuf -oL xargs -L 1 -n 1 -x -P 10 ./run-one.sh
