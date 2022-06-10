#!/bin/bash 

pushd $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI > /dev/null

SROOT=$( echo $ROOT_SCLI | sed -e s/client/sandbox/g )
echo "export ROOT_SBOX=$SROOT" > tconfig 
echo "export CURRENT_BUILD_SBOX=$CURRENT_BUILD_SCLI" >> tconfig 
cat ./.build-env >> tconfig 
cat build-config | grep SCLI_ | sed -e s/SCLI_/SBOX_/g | sed -e s/localhost:5000/localhost:6000/g | sed -e s/SIGNING_KEY/VERIFICATION_KEY/g | sed -e s/pharma-priv/pharma-pub/g | sed -e s/machine-pub/machine-priv/g | sed -e s/ROOT_SCLI/ROOT_SBOX/g | sed -e s/CURRENT_BUILD_SCLI/CURRENT_BUILD_SBOX/g >> tconfig
echo "export SBOX_DK_FILE=\$SBOX_EPK_FILE-dk" >> tconfig

# copy files
source ./tconfig

if [ ! -d "$SBOX_ROOT" ]; then
	echo "Please create sandbox at $SBOX_ROOT and retry"
	popd > /dev/null
	exit 1
fi

mv tconfig $SBOX_ROOT/config
mkdir -p $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX > /dev/null
#if [ -d $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX ]; then
#	echo Exists: $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX
#else
#	echo Does not exist: $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX
#fi


cp ./.env-eb $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.
cp $SCLI_MEAS_FILE $SBOX_MEAS_FILE
cp $SCLI_EPK_FILE $SBOX_EPK_FILE

cat $SBOX_ROOT/config | sed -e "s@$HOME@\$HOME@g" > tconfig
grep -v "ROOT_SBOX=" tconfig > ttconfig
echo "export ROOT_SBOX=\$HOME/sample/sandbox" > tttconfig
cat ttconfig >> tttconfig

mv tttconfig $SBOX_ROOT/config

ssh -i $SECURESTREAM_PLATFORM_TRANSFER_KEY_FILE -o "StrictHostKeyChecking no" $SECURESTREAM_PLATFORM_USERNAME@$SECURESTREAM_PLATFORM_ADDRESS "mkdir -p sample"
scp -rp -o "StrictHostKeyChecking no"  -i $SECURESTREAM_PLATFORM_TRANSFER_KEY_FILE $SBOX_ROOT $SECURESTREAM_PLATFORM_USERNAME@$SECURESTREAM_PLATFORM_ADDRESS:~/sample

#rm -rf $SBOX_ALGO_DATA/algorithm-input/*
#cp -R $SCLI_ALGO_DATA/algorithm-input/* $SBOX_ALGO_DATA/algorithm-input/

popd > /dev/null
