#!/usr/bin/env bash

###
# Configure the script (this is the only part to edit)
###

# setting a new device key changes one physical device from one logical device in the backend
# to another one. This is useful to change device keys if they got leaked.
NEW_DEVICE_KEY=

# Edit the relevant values below to to set os.network.connectivty
# See more details at https://github.com/balena-os/meta-balena#connectivity
# Example:
# CONNECTIVITY_URI="https://api.balena-cloud.com/connectivity-check"
# CONNECTIVITY_INTERVAL=120
# CONNECTIVITY_RESPONSE=
CONNECTIVITY_URI=
CONNECTIVITY_INTERVAL=3600
CONNECTIVITY_RESPONSE=

# Edit COUNTRY for the relevant wifi regulatory domain country
# See more details at https://github.com/balena-os/meta-balena#country
# The country code should be the ISO 3166-1 alpha-2 code for the
# relevant country https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
# Example (being in the United Kingdom)
# COUNTRY="GB"
COUNTRY=

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

# Edit DOMAIN_UPDATE to set the domains to "balena-cloud.com" instead of "resin.io"
# The accepted values are "true" and "false", anything else will be discarded
# Example: DOMAIN_UPDATE="true"
DOMAIN_UPDATE="true"

# Edit CLOUDLINK_UPDATE to set the vpnEndpoint to "cloudlink" instead of "vpn"
# The accepted values are "true" and "false", anything else will be discarded
# Example: CLOUDLINK_UPDATE="true"
CLOUDLINK_UPDATE="true"

# Edit RANDOMMACADDRESSSCAN to set .os.network.wifi.randomMacAddressScan value
# See more details at https://github.com/balena-os/meta-balena#wifi
# The accepted values are "true" and "false", anything else will be discarded
# Example: RANDOMMACADDRESSSCAN="false"
RANDOMMACADDRESSSCAN=

# Edit the SSHKEYS array to add your ssh-key, similar to this example:
# SSHKEY=("ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3rIsl4KO2zasaRSC4U6eauGqy5E6zuq4wgApKfzXjjIdtNHfYMC28CCCJvDbbaM2qx02z1x2XsxhvsIVI5+8VNNMXiy9/KRZGqpi1DK4R41k5NgyXW1RtU4CfOU4nFriVif1xq7d96qJTfvDUS47Vbr2aRT001Gq5Qh5Oo+p+YQVhWqn1I4A4VEYCXp69Vn/agZTww6yGnQRCU4Du5WKOTfrEw/BPbNLhndPNejgES+lPiGjTDW3m9rFaWM99TwuI7vQ6Gi+GXwfPCWlhR1frh9fifT8PFw9hhaoTv8q+f/hBuIOcfmWYZ38JfCWrgvYGfNoMiGNY33dd19CmJXgf nobody@nowhere")
# If you want to add more than one, set it as space separated strings, meaning
# SSHKEYS=("<firstkey>" "<secondkey>" "<thirdkey>")
SSHKEYS=()

# Edit/add the UDEVRULES variable to add your UDEV rules
# Please don't change the line just below this:
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

countryInsert() {
    echo "Inserting country values"
    local TEMPWORK
    TEMPWORK=$(tempwork)
    jq ".country = \"${COUNTRY}\"" "$WORKCONFIGFILE" > "$TEMPWORK" || finish_up "Couldn't insert country value"
    if [[ "$(jq -e '.country' "${TEMPWORK}")" == "" ]] ; then
        finish_up "Failed to insert country into config.json."
    fi
    mv "${TEMPWORK}" "${WORKCONFIGFILE}" || finish_up "Failed to update working copy of config.json"
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

networkPostInsert() {
    echo "Running dnsServers post insert tasks"
    systemctl restart resin-net-config || true
}

postDeviceIdentityChange() {
    echo "Restarting services after identity change"
    # this should happen after we close the SSH connection, 
    # therefore nohup + spawning
    nohup sh -c "sleep 10 ; systemctl restart openvpn" &
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

###
# Handling os.network.connectivity
###

connectivityInsert() {
    echo "Inserting .os.network.connectivity values"
    local TEMPWORK
    TEMPWORK=$(tempwork)
    jq ".os.network.connectivity.uri = \"${CONNECTIVITY_URI}\" | .os.network.connectivity.interval = \"${CONNECTIVITY_INTERVAL}\" | .os.network.connectivity.response = \"${CONNECTIVITY_RESPONSE}\"" "$WORKCONFIGFILE" > "$TEMPWORK" || finish_up "Couldn't insert .os.network.connectivit value"
    if [[ "$(jq -e '.os.network.connectivity.uri' "${TEMPWORK}")" == "" ]] ; then
        finish_up "Failed to insert .os.network.connectivit into config.json."
    fi
    mv "${TEMPWORK}" "${WORKCONFIGFILE}" || finish_up "Failed to update working copy of config.json"
}

newDeviceKeyInsert() {
    echo "Inserting .deviceApiKey value"
    local TEMPWORK
    TEMPWORK=$(tempwork)
    CLOUD_ENV=$(jq -j .apiEndpoint "$WORKCONFIGFILE" | sed 's/.*\///')
    jq ".deviceApiKey = \"${NEW_DEVICE_KEY}\" | .deviceApiKeys.\"${CLOUD_ENV}\" = \"${NEW_DEVICE_KEY}\" " "$WORKCONFIGFILE" > "$TEMPWORK" || finish_up "Couldn't insert .deviceApiKey value"
    if [[ "$(jq -e '.deviceApiKey' "${TEMPWORK}")" == "" ]] ; then
        finish_up "Failed to insert .deviceApiKey into config.json."
    fi
    mv "${TEMPWORK}" "${WORKCONFIGFILE}" || finish_up "Failed to update working copy of config.json"
}


###
# Handling domain update
###
domainUpdate() {
  echo "Updating the domain to balena-cloud.com instead of resin.io"
  local TEMPWORK
  TEMPWORK=$(tempwork)
  case ${DOMAIN_UPDATE} in
      "true"|"false")
          if [[ ${DOMAIN_UPDATE} == "true" ]]; then
            cat "$WORKCONFIGFILE" | sed 's/resin.io/balena-cloud.com/g' > "$TEMPWORK"|| finish_up "Couldn't change domain to balena-cloud.com"
            if [[ "$(jq -e '.apiEndpoint' "${TEMPWORK}")" == "" ]] ; then
                finish_up "Failed to change the domains into config.json."
            fi
            mv "${TEMPWORK}" "${WORKCONFIGFILE}" || finish_up "Failed to update working copy of config.json"
          fi
          ;;
      *)
          echo "Invalid value set for DOMAIN_UPDATE variable, ignoring"
  esac
}

###
# Handling vpnEndpoint updates
###
cloudlinkUpdate() {
    echo "Updating VPN URL to cloudlink"
    local TEMPWORK
    TEMPWORK=$(tempwork)
    case ${CLOUDLINK_UPDATE} in
        "true"|"false")
            if [[ ${CLOUDLINK_UPDATE} == "true" ]]; then
              jq ".vpnEndpoint = \"cloudlink.balena-cloud.com\"" "$WORKCONFIGFILE" > "$TEMPWORK" || finish_up "Couldn't insert correct vpnEndpoint value"
              if [[ "$(jq -e '.vpnEndpoint' "${TEMPWORK}")" == "" ]] ; then
                  finish_up "Failed to insert correct vpnEndpoint into config.json."
              fi
              mv "${TEMPWORK}" "${WORKCONFIGFILE}" || finish_up "Failed to update working copy of config.json"
            fi
            ;;
        *)
            echo "Invalid value set for CLOUDLINK_UPDATE variable, ignoring"
    esac
}

###
# Handling .os.network.wifi.randomMacAddressScan
###

randommacInsert() {
    echo "Inserting .os.network.wifi.randomMacAddressScan values"
    local TEMPWORK
    TEMPWORK=$(tempwork)
    case ${RANDOMMACADDRESSSCAN} in
        "true"|"false")
            jq ".os.network.wifi.randomMacAddressScan = ${RANDOMMACADDRESSSCAN}" "$WORKCONFIGFILE" > "$TEMPWORK" || finish_up "Couldn't insert randomMacAddressScan value"
            if [[ "$(jq -e '.os.network.wifi.randomMacAddressScan' "${TEMPWORK}")" == "" ]] ; then
                finish_up "Failed to insert randomMacAddressScan into config.json."
            fi
            mv "${TEMPWORK}" "${WORKCONFIGFILE}" || finish_up "Failed to update working copy of config.json"
            ;;
        *)
            echo "Invalid value set for RANDOMMACADDRESSSCAN variable, ignoring"
    esac
}

networkmanagerPostInsert() {
    echo "Running .os.network.* post insert tasks"
    systemctl restart os-networkmanager || true
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
    if [[ "${NEW_DEVICE_KEY}" != "" ]]; then
        DO_NEW_DEVICE_KEY="yes"
        anytask="yes"
    fi
    if [[ "${CONNECTIVITY_URI}" != "" ]]; then
        DO_CONNECTIVITY="yes"
        anytask="yes"
    fi
    if [[ "${COUNTRY}" != "" ]]; then
        DO_COUNTRY="yes"
        anytask="yes"
    fi
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
    if [[ "${DOMAIN_UPDATE}" != "" ]]; then
        DO_DOMAINUPDATE="yes"
        anytask="yes"
    fi
    if [[ "${CLOUDLINK_UPDATE}" != "" ]]; then
        DO_CLOUDLINKUPDATE="yes"
        anytask="yes"
    fi
    if [[ "${RANDOMMACADDRESSSCAN}" != "" ]]; then
        DO_RANDOMMACADDRESSSCAN="yes"
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
    if [[ "${DO_NEW_DEVICE_KEY}" == "yes" ]]; then
        newDeviceKeyInsert
    fi
    if [[ "${DO_CONNECTIVITY}" == "yes" ]]; then
        connectivityInsert
    fi
    if [[ "${DO_COUNTRY}" == "yes" ]]; then
        countryInsert
    fi
    if [[ "${DO_DNSSERVERS}" == "yes" ]]; then
        dnsserversInsert
    fi
    if [[ "${DO_NTPSERVERS}" == "yes" ]]; then
        ntpserversInsert
    fi
    if [[ "${DO_SSHKEYS}" == "yes" ]]; then
        sshkeysInsert
    fi
    if [[ "${DO_DOMAINUPDATE}" == "yes" ]]; then
        domainUpdate
    fi
    if [[ "${DO_CLOUDLINKUPDATE}" == "yes" ]]; then
        cloudlinkUpdate
    fi
    if [[ "${DO_RANDOMMACADDRESSSCAN}" == "yes" ]]; then
        randommacInsert
    fi
    if [[ "${DO_UDEVRULES}" == "yes" ]]; then
        udevrulesInsert
    fi

    echo "Stopping supervisor before updating the original config.json"
    systemctl stop resin-supervisor || finish_up "Could not stop supervisor."

    # copy the config back
    mv "${WORKCONFIGFILE}" "${BASECONFIGFILE}"  || finish_up "Could not move final config.json back to the original location"
    sync -f "${BASECONFIGFILE}"

    # Post update tasks
    if [[ "${DO_COUNTRY}" == "yes" ]] || [[ "${DO_DNSSERVERS}" == "yes" ]]; then
        networkPostInsert
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
    if [[ "${DO_CONNECTIVITY}" == "yes" ]] || [[ "${DO_RANDOMMACADDRESSSCAN}" == "yes" ]]; then
        networkmanagerPostInsert
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
    if ! balena ps | grep -q "\(resin\|balena\)_supervisor" ; then
        finish_up "Supervisor not restarted properly after while."
    fi

    if [[ "${DO_NEW_DEVICE_KEY}" == "yes" ]] ; then
        # this will kill the VPN connection after some timeout, so be sure to keep this last!
        postDeviceIdentityChange
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
