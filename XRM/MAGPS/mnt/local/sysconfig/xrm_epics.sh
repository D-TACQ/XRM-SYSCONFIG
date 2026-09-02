#!/bin/sh

echo 1>&2 xrm_epics.sh
export ACQ400IOC=ACQ400IOCnum
# XRM IOC HOST - eg. ACQ400IOC + 500
export IOC_HOST=XRMIOCnum
# connects to custom NIC on eigg
#ifconfig eth0:0 192.168.1.88 up
# pick an unused address that's visible on Peter's vpn
# ifconfig eth0:0 10.12.198.98 netmask 255.255.252.0 up
#ETH00_IP=10.12.198.98
#NETMASK=255.255.252.0
#ifconfig eth0:0 $ETH00_IP  up netmask $NETMASK
export ETH0_IP=$(/usr/local/CARE/ip_addr_show eth0)
export ETH00_IP=$ETH0_IP:44000
export EPICS_CAS_INTF_ADDR_LIST=$ETH00_IP
export EPICS_PVAS_INTF_ADDR_LIST=$ETH00_IP
#export EPICS_CAS_BEACON_ADDR_LIST=192.168.1.88

# bind client (including in-server client) to both

export EPICS_CA_ADDR_LIST="$ETH0_IP $ETH00_IP"
export EPICS_PVA_ADDR_LIST="$ETH0_IP $ETH00_IP"

#export XRM_MODEL="XRM-INST-A"
#export XRM_MODEL="XRM-INST-B"
export XRM_MODEL="XRM-MagPS"
#export XRM_MODEL="XRM-QPMS"

#deduce_xrm_part() {
#	echo @@todo_xrm_part_auto-deduction
#}
#export XRM_PART=$(deduce_xrm_part)

## --- Select functions --- ##
#export XRM_FMT_SIM=1
export XRM_FMT_RX=1
export XRM_SOE=1
export XRM_PM=1
export XRM_PRMT=1
export XRM_INST1="STRATEGY=STR;REDIS_HOST=radish;REDIS_PORT=6379;"
export IN1STR_cmd=/usr/local/bin/redis-acq400
export XRM_INST2="STRATEGY=SPY;REDIS_HOST=radish;REDIS_PORT=6379;"
#export IN2SPY_cmd=/usr/local/bin/redis-acq400
export IN2SPY_cmd=/usr/local/bin/redis-acq400

export MultiCastVerbose=1

# redundant
#export acq400_SOE_Strategy=LUT_FMT1
