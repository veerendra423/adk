#!/bin/bash

if [ -z "$SBOX_ALGO_DIR" ]; then
        echo "Please export SBOX_ALGO_DIR and try again"
        exit 1
else
	H_DIR=$SBOX_ALGO_DIR
fi

C_DIR=/algo

if [ -z "$SBOX_ALGO_DATA" ]; then
	echo "Please export SBOX_ALGO_DATA and try again (Note: SBOX_ALGO_DATA must NOT be in SBOX_ALGO_DIR)"
        exit 1
else 
	AD=$( echo $SBOX_ALGO_DATA | sed -e "s@$SBOX_ALGO_DIR@$C_DIR@g")
	if [ $AD != $SBOX_ALGO_DATA ]; then
		echo "Please change your SBOX_ALGO_DATA so the name doesn't conflict with SBOX_ALGO_DIR"
		exit 1
	fi
fi

if [ ! -d $H_DIR ]; then
	echo Directory $H_DIR does not exist
	exit 1
fi

if [ $1 != "sensec" ]; then
	echo $1 not a Sensoriant command
	exit 1
fi

SENSECMD=${@:1}
SENSECMD_UPDATED_PATHS=$( echo $SENSECMD | sed -e "s@$H_DIR@$C_DIR@g")

#echo $SENSECMD_UPDATED_PATHS

#eval docker run --rm -e SCLI_SBOX=sbox --privileged $NETMODE $VOL -it scli $SENSECMD_UPDATED_PATHS
pushd ./image > /dev/null
if [ $SBOX_SUPPRESS_CMD_RCVD == true ]; then
	docker-compose run --rm SensCli $SENSECMD_UPDATED_PATHS | tail -1 | jq -c 'del(."Command rcvd")'
else
	docker-compose run --rm SensCli $SENSECMD_UPDATED_PATHS | tail -1 
fi 
retcode=${PIPESTATUS[0]}
popd  > /dev/null

exit $retcode
