echo -1 >/etc/acq400/0/OVERSAMPLING
export EPICS_CA_MAX_ARRAY_BYTES=500000
# uncomment for live spectra, but not recommended for production use
# as it can result in loss of data in some conditions
#export IOC_PREINIT=./scripts/load.SpecReal
#[ -e /dev/shm/window ] || \
#	ln -s /usr/local/CARE/hanning-float.bin /dev/shm/window

# if we have two Ethernets,restrict CA to eth0, otherwise, leave ioc to work it out
ETH1=$(get-ip-address eth1)
if [ $? -eq 0 ]; then
	ETH0=$(get-ip-address eth0)
	if [ $? -eq 0 ]; then
		export EPICS_CAS_INTF_ADDR_LIST="$ETH0 $(get-ip-address lo)"
	fi
fi

judgement() {
# short trace length, rapid update 50Hz possible
# $1:size, $2:dX (don't care) $3:BPB
	export SIZE=${1:-128}
# round to the nearest 10
	export SIZE=$((${SIZE%[0123456789]*}*10))
	export IOC_PREINIT=./scripts/load.judgement
	export BURSTS_PER_BUFFER=${3:-1}
	export RTM_BUFFER_MON=y
	export RTM_BUFFER_MON_VERBOSE=1
}

judgement_nj() {
# nj: "no judgment"
# short trace length, rapid update 50Hz possible
# continuous, not burst
# $1:size, $2:dX (don't care) $3:BPB
	export SIZE=${1:-128}
# round to the nearest 10
	export SIZE=$((${SIZE%[0123456789]*}*10))
	export acq400Judgement_STUB_ES=1
	export acq400JudgementNJ=1
	export IOC_PREINIT=./scripts/load.judgement
}

# execution starts here


## normal judgement controlled from one place.
source /mnt/local/sysconfig/acq400.sh
if [ ! -z "$ACQ400_JUDGEMENT" ]; then
	judgement $ACQ400_JUDGEMENT
elif [ ! -z "$ACQ400_JUDGEMENT_NJ" ]; then
# uncomment if packed24
#export acq400JudgementNJ_P24=1
	judgement_nj $ACQ400_JUDGEMENT_NJ
fi

# Disable calibration monitoring sequences in acq400ioc
# DISABLE_CALMON=1
