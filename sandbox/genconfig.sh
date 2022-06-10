#!/bin/bash
echo "source ./standalone.config >/dev/null" > config 
#echo export ROOT_SBOX=\$HOME/sample/sandbox >> config
echo export ROOT_SBOX=$PWD >> config
echo export CURRENT_BUILD_SBOX=default >> config
echo export SBOX_ROOT=\$ROOT_SBOX >> config
echo export SBOX_REGISTRY=localhost:6000 >> config
echo export SBOX_ALGO_DIR=\$SBOX_ROOT/image/sdata >> config
echo export SBOX_MEAS_FILE=\$SBOX_ALGO_DIR/\$CURRENT_BUILD_SBOX/image.enc-meas.txt >> config
echo export SBOX_IPK_FILE=\$SBOX_ALGO_DIR/\$CURRENT_BUILD_SBOX/image.enc-priv.pem >> config
echo export SBOX_EPK_FILE=\$SBOX_IPK_FILE-ek >> config
echo export SBOX_VERIFICATION_KEY=\$SBOX_ALGO_DIR/image-ver-pub.pem >> config
echo export SBOX_MACHINE_KEY=\$SBOX_ALGO_DIR/machine-priv.pem >> config
echo export SBOX_DK_FILE=\$SBOX_EPK_FILE-dk >> config
echo export SBOX_ALGO_DATA=\$ROOT_SBOX/image/volumes >> config
SBOX_DOMAIN=`jq -r '.algorithm.signatureVerification.domain' $1`
echo export SBOX_DOMAIN=$SBOX_DOMAIN >> config
SBOX_IMAGE_FULLNAME=`jq -r '.algorithm.id' $1 | sed  's/https:\/\///g' | sed 's/@.*//'`
echo export SBOX_IMAGE_FULLNAME=$SBOX_IMAGE_FULLNAME >> config
echo export SBOX_IMAGE_UNENC_NAME=`echo $SBOX_IMAGE_FULLNAME | sed  's/.enc:/:/g'` >> config
source ./config
#
# Following block of exports needed by real product sandbox
echo export SBOX_ALGO_CONFIGS_PATH=\$SBOX_ALGO_DIR/\$CURRENT_BUILD_SBOX >> config
echo export SBOX_OUTPUT_RCVR_KEY=\$SBOX_ALGO_DIR/output-rcvr-pub.pem >> config
echo export SBOX_OUTPUT_DATASET_NAME=`jq -r '.output.name' $1` >> config
echo export SBOX_DATASET_NAME=`jq -r '.dataset.name' $1` >> config
echo export SBOX_DATASET_ID=`jq -r '.dataset.id' $1` >> config
echo export SBOX_PIPELINE_ID=`jq -r '.pipelineId' $1` >> config
echo export SBOX_IMAGE_UNENC_LOCALNAME=`echo $SBOX_IMAGE_UNENC_NAME | sed  "s@$SBOX_SENSE_REG@$SBOX_REGISTRY@g"` >> config
echo export SBOX_SSP_ID=`jq -r '.secureStreamPlatform.id' $1` >> config
echo export SBOX_SSP_NAME=`jq -r '.secureStreamPlatform.name' $1` >> config
source ./config


IMAGEDIGEST=`jq -r '.algorithm.decryptionKeys.container.filesystemMeasurement' $1`
echo -n sha256:$IMAGEDIGEST > $SBOX_MEAS_FILE
jq -r '.algorithm.decryptionKeys.container.encryptedDecryptionKey' $1 | base64 -d > $SBOX_EPK_FILE
jq '.algorithm.signatureVerification.publicKey' $1 | sed -e s/\"//g | awk '{gsub(/\\n/,"\n")}1' > $SBOX_VERIFICATION_KEY
jq '.output.receiversPublicKey' $1 | sed -e s/\"//g | awk '{gsub(/\\n/,"\n")}1' > $SBOX_OUTPUT_RCVR_KEY

SBOX_ALGO_FSPF_TAG=`jq -r '.algorithm.decryptionKeys.enclave.filesystemMeasurement' $1`
echo FSPF_TAG=$SBOX_ALGO_FSPF_TAG > $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env

jq -r '.algorithm.decryptionKeys.enclave.encryptedDecryptionKey' $1 | base64 -d > $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/algorithm.decryptionKeys.enclave.decryptionKey-eb

jq -r '.output.encryptionKey.encryptedSymmetricKey' $1 | base64 -d > $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/output.encryptionkey.symmetrickey-eb

jq -r '.dataset.decryptionKey.encryptedSymmetricKey' $1 | base64 -d > $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/dataset.decryptionkey.symmetrickey-eb
