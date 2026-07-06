# external reboot control
REBOOT_KNOB=y
#
FANSPEED=100

# SSL: hostname.crt, hostname.key should reside in /mnt/local/sysconfig/ssl
# enable SSL (https://) with embedded certificate alongside http://
#SSL_MODE=ON
# enable SSL ONLY. Best to test with "ON" first
#SSL_MODE=FORCE
# set location of CA. Default shown below:
#SSL_CA_POPUP_LINK=https://www.d-tacq.com/acq400_ssl.shtml
# password protection for web site. i
# password is held /mnt/local/sysconfig/auth
#SSL_MODE=FORCE
#WEB_AUTH=ON

# optional external rsyslog HOST
#RSYSLOG_HOST=naboo
# optional, expert tailor number of buffers
#NBUF=128
# optional, expert tailor buffer allocated length
#BLEN=4194304
# optional, specialist: control MULTI_EVENT
#MULTI_EVENT=100000,100000,100,0
#MULTI_EVENT_DISK=yes
# scaled rate status for CONTINUOUS OPI
#STREAM_OPTS=--fill-scale
# ETH1000LX - connect to SFPD (MGT482 systems only)
#ETH1_E1000X=y

# ACQ400_JUDGEMENT: Burst mode rapid update, with mask and stats
# Rapid Scope, 256 points, external trigger to 50Hz
#ACQ400_JUDGEMENT="256 d0"
# Rapid Scope, 256 points, internal trigger to 50Hz
#ACQ400_JUDGEMENT="256 d1"
# Rapid Scope, 1024 points, internal trigger to 10Hz
#ACQ400_JUDGEMENT="1024 d1"
# Rapid Scope, 4096 points, internal trigger to 2Hz
#ACQ400_JUDGEMENT="4096 d1"
# for normal streaming, leave all ACQ400_JUDGEMENT above commented out

# for rapid update with normal streaming, not burst
# Rapid update, no trigger, No Judgment:
#ACQ400_JUDGEMENT_NJ="1024"

# Box specific initialization
echo "XRM specific flavor initialization"
XRM_MODEL=$(grep ^export /mnt/local/sysconfig/xrm_epics.sh | grep MODEL | sed 's/.*="//;s/"//')
echo "Detected XRM flavor : $XRM_MODEL"

APPLIANCE_TYPE=$XRM_MODEL
if [ "$APPLIANCE_TYPE" == "XRM-MagPS" ]; then
	XRM_JUDGEMENT="4096 d0"
elif [ "$APPLIANCE_TYPE" == "XRM-QPMS" ]; then
	XRM_JUDGEMENT="4096 d0"
elif [ "$APPLIANCE_TYPE" == "XRM-INST-A" ]; then
	XRM_JUDGEMENT="16384 d0"
elif [ "$APPLIANCE_TYPE" == "XRM-INST-B" ]; then
	XRM_JUDGEMENT="16384 d0"
elif [ "$APPLIANCE_TYPE" == "XRM-ALLISON" ]; then
	#XRM_JUDGEMENT="20000 d0"
	echo "no Judgement on Allison, stops RT from working"
else
	echo "No XRM detected"
fi


BLEN=4194304
NBUF=40
