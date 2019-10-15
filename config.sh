#!/usr/bin/env bash

###
# Configure the script (this is the only part to edit)
###

# Edit the DNSERVERS string to add specific DNS servers (dnsServers config.json variable)
# The string is space separated list of servers
# See more details at https://github.com/balena-os/meta-balena#dnsservers
# Example: DNSSERVERS="1.1.1.1 8.8.8.8 8.8.4.4"
DNSSERVERS=""

# Edit the NTPSERVERS string to add specific NTP servers (ntpServers config.json variable)
# The string is space separated list of servers
# See more details at https://github.com/balena-os/meta-balena#ntpservers
# Example: NTPSERVERS="0.uk.pool.ntp.org 0.europe.pool.ntp.org 0.pool.ntp.org"
NTPSERVERS=""

# Edit the SSHKEYS array to add your ssh-key, similar to this example:
# SSHKEY=("ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3rIsl4KO2zasaRSC4U6eauGqy5E6zuq4wgApKfzXjjIdtNHfYMC28CCCJvDbbaM2qx02z1x2XsxhvsIVI5+8VNNMXiy9/KRZGqpi1DK4R41k5NgyXW1RtU4CfOU4nFriVif1xq7d96qJTfvDUS47Vbr2aRT001Gq5Qh5Oo+p+YQVhWqn1I4A4VEYCXp69Vn/agZTww6yGnQRCU4Du5WKOTfrEw/BPbNLhndPNejgES+lPiGjTDW3m9rFaWM99TwuI7vQ6Gi+GXwfPCWlhR1frh9fifT8PFw9hhaoTv8q+f/hBuIOcfmWYZ38JfCWrgvYGfNoMiGNY33dd19CmJXgf nobody@nowhere")
# If you want to add more than one, set it as space separated strings, meaning
# SSHKEYS=("<firstkey>" "<secondkey>" "<thirdkey>")
SSHKEYS=()

# Edit/add the UDEVRULES variable to add your UDEV rules
declare -A UDEVRULES
# * Step 1: `jq -sR . < rulefilename` and replace the outside the outside double quotes " with single quotes '
# * Add a new line as UDEVRULES[rulename]='<the contents of the previous step>'
# * To add multiple rules, create multiple lines with different rulenames
# * An example rule is just below.
# UDEVRULES[20-something]='ACTION==\"add\", SUBSYSTEM==\"net\", ATTRS{idVendor}==\"7392\", ATTRS{idProduct}==\"7811\", NAME=\"extAP\"\n'

# Whether or not restart the engine if the supervisor restart failed.
FORCE_SUPERVISOR_RESTART="no"

###
# End of script configuration
###

set -o errexit -o pipefail

# Don't run anything before this source as it sets PATH here
# shellcheck disable=SC1091
source /etc/profile

BASECONFIGFILE="/mnt/boot/config.json"

###
# Helper functions
###

# Finish up the script
# If message passed as an argument, that means failure.
finish_up() {
  local message=$1
  if [ -n "${message}" ]; then
    echo "FAIL: ${message}"
    exit 1
  else
    echo "DONE"
    exit 0
  fi
}

tempwork() {
    local TEMPWORK
    TEMPWORK=$(mktemp -t "config.json.work.XXXXXXXXXX") || finish_up "Could not create temporary work file."
    echo "${TEMPWORK}"
}

###
# Handling dnsServers
###

dnsserversInsert() {
    echo "Inserting dnsServers values"
    local TEMPWORK
    TEMPWORK=$(tempwork)
    jq ".dnsServers = \"${DNSSERVERS}\"" "$WORKCONFIGFILE" > "$TEMPWORK" || finish_up "Couldn't insert ntpServers value"
    if [[ "$(jq -e '.dnsServers' "${TEMPWORK}")" == "" ]] ; then
        finish_up "Failed to insert sshKeys into config.json."
    fi
    mv "${TEMPWORK}" "${WORKCONFIGFILE}" || finish_up "Failed to update working copy of config.json"
}

dnsserversPostInsert() {
    echo "Running dnsServers post insert tasks"
    systemctl restart resin-net-config || true
}

###
# Handling ntpServers
###

ntpserversInsert() {
    echo "Inserting ntpServers values"
    local TEMPWORK
    TEMPWORK=$(tempwork)
    jq ".ntpServers = \"${NTPSERVERS}\"" "$WORKCONFIGFILE" > "$TEMPWORK" || finish_up "Couldn't insert ntpServers value"
    if [[ "$(jq -e '.ntpServers' "${TEMPWORK}")" == "" ]] ; then
        finish_up "Failed to insert sshKeys into config.json."
    fi
    mv "${TEMPWORK}" "${WORKCONFIGFILE}" || finish_up "Failed to update working copy of config.json"
}

ntpserversPostInsert() {
    echo "Running ntpServers post insert tasks"
    /usr/bin/resin-ntp-config || true
}

###
# Handling sshKey
###
sshkeysInsert() {
    echo "Inserting sshKeys values"
    local TEMPWORK
    TEMPWORK=$(tempwork)
    local update_command=".os.sshKeys += [ "
    local -i numkeys=${#SSHKEYS[@]}
    for keyindex in "${!SSHKEYS[@]}"; do
        echo "Keyindex: ${keyindex}"
        update_command+=" \"${SSHKEYS[$keyindex]}\" "
        if (( keyindex < (numkeys-1) )) ; then
            update_command+=", "
        fi
    done
    update_command+=" ]"
    jq "${update_command}" "${WORKCONFIGFILE}" > "${TEMPWORK}" || finish_up "Failed to create new json with sshKeys inserted."
    if [[ "$(jq -e '.os.sshKeys' "${TEMPWORK}")" == "" ]] ; then
        finish_up "Failed to insert sshKeys into config.json."
    fi
    mv "${TEMPWORK}" "${WORKCONFIGFILE}" || finish_up "Failed to update working copy of config.json"
}

sshkeysPostInsert() {
    echo "Running sshKeys post insert tasks"
    systemctl restart os-sshkeys || finish_up "ssh keys service did not restart successfully."
}

# Handling udevRules
udevrulesInsert() {
    echo "Inserting udevRules values"
    local TEMPWORK
    TEMPWORK=$(tempwork)
    for key in "${!UDEVRULES[@]}" ; do
        jq  ".os.udevRules.\"${key}\" = \"${UDEVRULES[$key]}\"" "$WORKCONFIGFILE" > "$TEMPWORK" || finish_up "Couldn't insert rule ${key}."
        if [[ "$(jq -e ".os.udevRules.\"${key}\"" "$TEMPWORK")" == "" ]] ; then
            finish_up "Failed to insert ${key} rule into config.json."
        fi
        mv "${TEMPWORK}" "${WORKCONFIGFILE}" || finish_up "Failed to update working copy of config.json"
    done
}

udevrulesPostInsert() {
    echo "Running udevRules post insert tasks"
    if systemctl is-active --quiet os-udevrules ; then
        # Only run this if there's a relevant service
        systemctl restart os-udevrules || finish_up "udev rules service did not restart successfully."
    fi
}

###
# Task starts here
###
main() {
    local anytask="no"

    # Check what tasks need to be done
    if [[ "${DNSSERVERS}" != "" ]]; then
        DO_DNSSERVERS="yes"
        anytask="yes"
    fi
    if [[ "${NTPSERVERS}" != "" ]]; then
        DO_NTPSERVERS="yes"
        anytask="yes"
    fi
    if (( ${#SSHKEYS[@]} > 0 )); then
        DO_SSHKEYS="yes"
        anytask="yes"
    fi
    if (( ${#UDEVRULES[@]} > 0 )); then
        DO_UDEVRULES="yes"
        anytask="yes"
    fi

    # If any tasks, create a working copy of the config.json otherwise bail
    if [[ "${anytask}" != "yes" ]]; then
        echo "No task set, finishing"
        finish_up
    else
        WORKCONFIGFILE=$(mktemp -t "config.json.tmp.XXXXXXXXXX") || finish_up "Could not create work temp file."
        cp "${BASECONFIGFILE}" "${WORKCONFIGFILE}" || finish_up "Could not copy config.json to temporary location."
    fi

    # Do update tasks
    if [[ "${DO_DNSSERVERS}" == "yes" ]]; then
        dnsserversInsert
    fi
    if [[ "${DO_NTPSERVERS}" == "yes" ]]; then
        ntpserversInsert
    fi
    if [[ "${DO_SSHKEYS}" == "yes" ]]; then
        sshkeysInsert
    fi
    if [[ "${DO_UDEVRULES}" == "yes" ]]; then
        udevrulesInsert
    fi

    echo "Stopping supervisor before updating the original config.json"
    systemctl stop resin-supervisor || finish_up "Could not stop supervisor."

    # copy the config back
    mv "${WORKCONFIGFILE}" "${BASECONFIGFILE}"  || finish_up "Could not move final config.json back to the original location"

    # Post update tasks
    if [[ "${DO_DNSSERVERS}" == "yes" ]]; then
        dnsserversPostInsert
    fi
    if [[ "${DO_NTPSERVERS}" == "yes" ]]; then
        ntpserversPostInsert
    fi
    if [[ "${DO_SSHKEYS}" == "yes" ]]; then
        sshkeysPostInsert
    fi
    if [[ "${DO_UDEVRULES}" == "yes" ]]; then
        udevrulesPostInsert
    fi

    # Restart the supervisor
    echo "Restarting supervisor."
    if ! systemctl restart resin-supervisor ; then
        if [[ "${FORCE_SUPERVISOR_RESTART}" = "yes" ]] ; then
            echo "First supervisor restart attempt didn't work, trying with balenaEngine restart"
            systemctl stop resin-supervisor || finish_up "Couldn't stop supervisor."
            systemctl stop balena || finish_up "Couldn't stop balena."
            systemctl start balena || finish_up "Couldn't start up balena."
            systemctl start resin-supervisor || finish_up "Couldn't start up supervisor."
        else
            echo "First supervisoe restart attempt didn't work, but not retrying."
        fi
    fi
    sleep 10
    if ! balena ps | grep -q resin_supervisor ; then
        finish_up "Supervisor not restarted properly after while."
    fi
    # All done
    finish_up
}

(
  # Check if already running and bail if yes
  flock -n 99 || (echo "Already running script..."; exit 1)
  main
) 99>/tmp/config.lock
# Proper exit, required due to the locking subshell
exit $?
