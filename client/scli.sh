#!/bin/bash

if [ -z "$SCLI_ALGO_DIR" ]; then
        echo "Please export SCLI_ALGO_DIR and try again"
        exit 1
else
	H_DIR=$SCLI_ALGO_DIR
fi

if [ ! -d $H_DIR ]; then
	echo Directory $H_DIR does not exist
	exit 1
fi

if ! test -f "$SCLI_ALGO_DIR/$GCS_CREDS_FILE_NAME"; then
        echo Warning: $SCLI_ALGO_DIR/$GCS_CREDS_FILE_NAME does not exist!!
        GCS_CREDS_FILE_NAME=unknown_file

fi

if [ $1 != "sensec" ]; then
	echo $1 not a Sensoriant command
	exit 1
fi

if [ ! "$(docker ps -aq -f status=running -f name=clientregistry)" ]; then
	echo "Please run clientregistry and try again"
	exit 1
fi

# this must match the container directory in docker-compose
C_DIR=/algo

SENSECMD=${@:1}
SENSECMD_UPDATED_PATHS=$( echo $SENSECMD | sed -e "s@$H_DIR@$C_DIR@g")

#docker run --rm -e GOOGLE_APPLICATION_CREDENTIALS=$C_DIR/$GCS_CREDS_FILE_NAME $NETMODE $VOL -it scli $SENSECMD_UPDATED_PATHS

pushd ./image > /dev/null
docker-compose run --rm SensCli $SENSECMD_UPDATED_PATHS
popd > /dev/null
