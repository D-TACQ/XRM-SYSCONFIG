# clock tick: 25 nsec = 40MHz
WRTD_TICKNS=25
# time delay on trigger, 50msec is safe
WRTD_DELTA_NS=50000000
WRTD_VERBOSE=0
# we're going to run TX on demand to avoid multi-box race when trigger continuous
WRTD_RX=1
WRTD_TX=0
#WRTD_RX_MATCHES=dog,cat,rabbit,mouse
#export WRTD_RX_MATCHES=dog,cat,rabbit,mouse,acq2106_133.0
export WRTD_RX_MATCHES=$(hostname),ACQ400
export WRTD_ID=ACQ400
WRTD_OPTS=--rt_prio=15

