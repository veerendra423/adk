#!/bin/bash

if ! test -f "./config"; then
        echo "No config file!! Aborting ..."
        exit 1
fi

source ./config

all_vars=($(cat $SBOX_ALGO_CONFIGS_PATH/.env))

if [ ! $SBOX_KEEP_KEYS_ON_DISK = "true" ]; then
	rm -f $SBOX_ALGO_CONFIGS_PATH/.env > /dev/null
	rm -f $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/* > /dev/null
fi

for x in ${all_vars[@]}; do
        echo $x
done
