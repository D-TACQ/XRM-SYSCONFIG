#!/bin/sh

echo 1>&2 xrm_epics.sh
export IOC_HOST=acq2206_588
export ACQ400IOC=acq2206_088
ETH0_IP=$(/usr/local/CARE/ip_addr_show eth0)
ETH00_IP=$ETH0_IP:44000
# bind server to ETH00
export EPICS_CAS_INTF_ADDR_LIST=$ETH00_IP
export EPICS_PVAS_INTF_ADDR_LIST=$ETH00_IP
#export EPICS_CAS_BEACON_ADDR_LIST=192.168.1.88

# bind client (including in-server client) to both

export EPICS_CA_ADDR_LIST="$ETH0_IP $ETH00_IP"
export EPICS_PVA_ADDR_LIST="$ETH0_IP $ETH00_IP"

#export XRM_MODEL="XRM-INST-A"
#export XRM_MODEL="XRM-INST-B"
#export XRM_MODEL="XRM-MagPS"
#export XRM_MODEL="XRM-QPMS"
export XRM_MODEL="FMT-SIM"

#deduce_xrm_part() {
#	echo @@todo_xrm_part_auto-deduction
#}
#export XRM_PART=$(deduce_xrm_part)

export XRM_FMT_SIM=1
#export XRM_PROXY=1
#export XRM_FMT_RX=1
#export XRM_SOE=1
#export XRM_PM=1
#export XRM_INST1="STRATEGY=STR;REDIS_HOST=radish;REDIS_PORT=2468;"
#export IN1STR_cmd=/usr/local/xrm/epics/scripts/inst-str-fake
#export XRM_INST2="STRATEGY=SPY;REDIS_HOST=radish;REDIS_PORT=2468;"
#export IN2SPY_cmd=/usr/local/xrm/epics/scripts/inst-str-fake
#export IN2SPY_cmd=/usr/local/xrm/epics/scripts/inst-spy-fake

export MultiCastVerbose=1

# redundant
#export acq400_SOE_Strategy=LUT_FMT1

export acq400_PM_buffer_throttle_modulo=1
#export acq400_PM_VERBOSE=3
#export acq400_PROXY_VERBOSE=2


