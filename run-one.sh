#!/usr/bin/env bash

# * connect to the device with balena ssh, pipe in the task script, and
#   save the log with the UUID prepended

uuid=$1

# don't run if the device has already been processed
grep -a -q "${uuid} : DONE" config.log 2>/dev/null && exit 0

# these settings need to be handled separately because they need to be different 
# per-device even when processing a large batch
newKey=$(grep "${uuid}" new_keys | sed 's/.*\s*->\s*//')

(
	if [ -z "${newKey}" ]; then
		cat config.sh
	else
		echo "changing ${uuid} to new key ${newKey:0:5}..." >&2
		cat config.sh \
		| sed "s/^NEW_DEVICE_KEY=.*/NEW_DEVICE_KEY=${newKey}/"
	fi
) \
| balena ssh "${uuid}" \
| sed "s/^/${uuid} : /" \
| tee -a config.log
