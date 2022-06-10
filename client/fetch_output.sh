#!/bin/bash

if [ -z "$1" ]; then
    echo "Pipeline information not provided"
    exit 1
fi

if ! test -f "$1"; then
    echo "File ($1) doesn't exist!"
    exit 1
fi

# source config in case this utility is called from outside scli-menu
source ./config

plid=`cat $1 | jq -r '.pipelineId'`
odsn=`cat $1 | jq -r '.output.name'`

dsname=$plid-$odsn
# see if dataset is available
echo Checking if dataset is available
dsinfo=`curl -s -w "%{http_code}" --keepalive-time 30  --connect-timeout 500  --insecure -X GET "https://$SCLI_API_SERVER/secure_cloud_api/v1/datasets/by_name/$dsname" -H  "accept: application/json"`

if [ ! `echo $dsinfo | tail -c 4` == "200" ]; then
	echo "Output ($dsname) not yet available... try later ..."
	echo $dsinfo
	echo "Failed: Output DataSet is Not Available"
	exit 1
fi
echo "Success: Output DataSet is Available"

# see if dataset key is available
echo Checking if dataset key is available
dskname=$dsname-KEY
dskinfo=`curl -s -w "%{http_code}" --keepalive-time 30  --connect-timeout 500  --insecure -X GET "https://$SCLI_API_SERVER/secure_cloud_api/v1/datasets/keys/by_name/$dskname" -H  "accept: application/json"`
	
if [ ! `echo $dskinfo | tail -c 4` == "200" ]; then
	echo "Key ($dskname) not yet available... try later ..."
	echo $dskinfo
	echo "Failed: Output DataSet Key is Not Available"
	exit 1
fi
echo "Success: Output DataSet Key is Available"

# decrypt the symmetric key
symkeyfile=$SCLI_ALGO_DIR/tmpoutsymkey-eb
symdkfile=tmpoutsymkey-eb-dk
echo ${dskinfo%???} | jq -r '.encryptedSymmetricKey' | base64 -d > $symkeyfile
./scli.sh sensec sctr dk -eb $symkeyfile -mpk $SCLI_OUTPUT_PRIV_KEY --outdir $SCLI_ALGO_DIR
rm -f $symkeyfile

# pull the dataset
pushd ./image >> /dev/null
echo DataSetName=$dsname > .env
source .env
echo "Pulling files to GCS - ${DataSetName}"
#sudo rm -rf $SCLI_ALGO_DATA/decrypt-input/*  >> /dev/null
#sudo rm -rf $SCLI_ALGO_DATA/decrypt-input/.gitignore  >> /dev/null
##using gcspull image just to remove root owned files
#docker-compose run --rm -v $SCLI_ALGO_DATA/decrypt-input:/d-inp SenseGcsPull bash -c 'rm -rf /d-inp/* && rm -rf /d-inp/.gitignore' > /dev/null
docker run --rm -v $SCLI_ALGO_DATA/decrypt-input:/d-inp docker.io/library/bash:latest bash -c 'rm -rf /d-inp/* && rm -rf /d-inp/.gitignore' > /dev/null
docker-compose run --rm -e GCS_OBJECT_PREFIX="${DataSetName}" -v $SCLI_ALGO_DATA/decrypt-input:/opt/sensoriant/gcs/pull/filesFromBucket SensGcsPull
popd >> /dev/null

# decrypt the dataset
pushd ./image >> /dev/null
echo -n "SENSDECRYPT_FSPF_KEY=" > .env
cat $symkeyfile-db >> .env
source .env
docker-compose run --rm SensDecrypt
##using gcspull image just to remove root owned files
#docker-compose run --rm -v $SCLI_ALGO_DIR/:/d-inp SenseGcsPull bash -c 'rm -rf /d-inp/${symdkfile}' > /dev/null
docker run --rm -e symdkfile=${symdkfile} -v $SCLI_ALGO_DATA/decrypt-input:/d-inp docker.io/library/bash:latest bash -c 'rm -rf /d-inp/${symdkfile}' > /dev/null
popd >> /dev/null

echo "Decrypted test_metrics file:"
cat ./image/volumes/decrypt-output/test_metrics.json

#sudo rm -f ${symkeyfile-db}

echo "Done.."
