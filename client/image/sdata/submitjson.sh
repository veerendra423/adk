#!/bin/bash 

SCLI_DIGEST=$( cat $SCLI_MEAS_FILE | sed -e s/sha256:// )
SCLI_EPK_BASE64=`base64 -w0 $SCLI_EPK_FILE`
SCLI_ALGO_FSPF_TAG=`awk -F= '$1=="FSPF_TAG"{print $2}' $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/.env`
SCLI_SPP_MRENCLAVE=`awk -F= '$1=="MRENCLAVE_ALGORITHM"{print $2}' $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/.env`
SCLI_ALGO_FSPF_EKEY=`base64 -w0  $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/algorithm.decryptionKeys.enclave.decryptionKey-eb`
SCLI_OUTP_SYM_EKEY=`base64 -w0  $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/output.encryptionkey.symmetrickey-eb`
cat $SCLI_ALGO_DIR/pharma-pub.pem | sed -z "s/\n/\\\n/g" > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/tmpfile
SCLI_VER_KEY=`cat $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/tmpfile`
rm $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/tmpfile

if ! test -f "$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/ssp.json"; then
echo "{
  \"name\": \"DefaultSSP_$CURRENT_BUILD_SCLI\",
  \"id\": \"$CURRENT_BUILD_SCLI\",
  \"measurement\": \"`echo defaultmeasurement | base64 -w0 `\"
}" > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/tmpssp.json
SSPFILE=$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/tmpssp.json
else
	SSPFILE=$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/ssp.json
fi

if ! test -f "$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dsk.json"; then
echo "{
  \"name\": \"DefaultDSK_$CURRENT_BUILD_SCLI\",
  \"id\": \"$CURRENT_BUILD_SCLI\",
  \"encryptedSymmetricKey\": \"$SCLI_ALGO_FSPF_EKEY\",
  \"dataset\": {
    \"name\": \"DefaultDS_$CURRENT_BUILD_SCLI\",
    \"id\": \"$CURRENT_BUILD_SCLI\"
  }
}" > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/tmpdsk.json
DSKFILE=$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/tmpdsk.json
else
	DSKFILE=$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dsk.json
fi

if ! test -f "$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/algo.json"; then
	algostr=https://$SCLI_SENSE_REG/$SCLI_REPO/$SCLI_IMAGE.enc:${SCLI_TAG}_$CURRENT_BUILD_SCLI@$SCLI_DIGEST
else
	algostr=`cat $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/algo.json | jq -r '.id'`
fi

cat > $CURRENT_BUILD_SCLI/pipeline.json << EOL
{
  "pipelineName": "Sens_Pipeline_$CURRENT_BUILD_SCLI",
  "algorithm": {
    "id": "$algostr",
    "decryptionKeys": {
      "container": {
        "filesystemMeasurement": "$SCLI_DIGEST",
        "secureStreamPlatformMeasurement": $(cat $SSPFILE | jq '.measurement'),
        "encryptedDecryptionKey": "$SCLI_EPK_BASE64"
      },
      "enclave": {
        "filesystemMeasurement": "$SCLI_ALGO_FSPF_TAG",
        "enclaveMeasurement": "$SCLI_SPP_MRENCLAVE",
        "encryptedDecryptionKey": "$SCLI_ALGO_FSPF_EKEY"
      }
    },
    "signatureVerification": {
      "publicKey": "$SCLI_VER_KEY",
      "domain": "$SCLI_DOMAIN"
    }
  },
  "dataset": {
    "name": $(cat $DSKFILE | jq '.dataset.name'),
    "id": $(cat $DSKFILE | jq '.dataset.id'),
    "decryptionKey": {
      "name": $(cat $DSKFILE | jq '.name'),
      "id": $(cat $DSKFILE | jq '.id'),
      "encryptedSymmetricKey": $(cat $DSKFILE | jq '.encryptedSymmetricKey')
    }
  },
  "output": {
    "name": "Sens_Output_$CURRENT_BUILD_SCLI",
    "encryptionKey": {
      "name": "Sens_Dataset_Key_Name_$CURRENT_BUILD_SCLI",
      "encryptedSymmetricKey": "$SCLI_OUTP_SYM_EKEY"
    },
    "receiversPublicKey": "$SCLI_VER_KEY"
  },
  "secureStreamPlatform": {
    "name": $(cat $SSPFILE | jq '.name'),
    "id": $(cat $SSPFILE | jq '.id')
  }
}
EOL

if ! test -f "$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/ssp.json"; then
	rm $SSPFILE
fi

if ! test -f "$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dsk.json"; then
	rm $DSKFILE
fi

SROOT=$( echo $ROOT_SCLI | sed -e s/client/sandbox/g )
rm -f $SROOT/config > /dev/null
cp $CURRENT_BUILD_SCLI/pipeline.json $SROOT/pipeline.json

if [ $SCLI_STANDALONE == true ]; then
	echo "In Standalone mode ... Copying algorithm-input to local sandbox"
	rm -rf $SROOT/image/volumes/algorithm-input/* > /dev/null
    	cp -r $SCLI_ALGO_DATA/algorithm-input/* $SROOT/image/volumes/algorithm-input/
else
	pltempl=`curl -s -w "%{http_code}" --keepalive-time 30  --connect-timeout 500  --insecure -X GET "https://sensccf.eastus.cloudapp.azure.com/secure_cloud_api/v1/pipelines/templates?limit=10&skip=0" -H  "accept: application/json"`
	if [ ! `echo $pltempl | tail -c 4` == "200" ]; then
                echo ${pltempl%???}
                echo "Failed: GET Pipeline template"
                exit 1
	else
		# check if there are more than 0 templates
		templfound=`echo ${pltempl%???} | jq '.found'`
		if [ $templfound == 0 ]; then
			echo ${pltempl%???}
        		echo "Failed: Get Pipeline template"
			exit 1
		fi
        fi
        PLTEMPLID=`echo ${pltempl%???} | jq -r '.pipelineTemplates[0].id'`

	ODSNAME=`cat $CURRENT_BUILD_SCLI/pipeline.json | jq -r '.output.name'`
	PLSUB=`cat $CURRENT_BUILD_SCLI/pipeline.json`
	plret=`curl -s -w "%{http_code}" --keepalive-time 30  --connect-timeout 500  --insecure -X POST "https://$SCLI_API_SERVER/secure_cloud_api/v1/pipelines/create/$PLTEMPLID" -H  "accept: application/json" -H  "Content-Type: application/json" -d "$PLSUB"`
        if [ ! `echo $plret | tail -c 4` == "201" ]; then
               echo ${plret%???}
               echo "Failed: Create Pipeline"
               exit 1
        fi
	PLID=`echo ${plret%???} | jq -r '.id'`

	EXP_OUTPUT=$PLID-$ODSNAME
	echo Expected GCS bucket file name: $EXP_OUTPUT

	echo $PLSUB | jq --arg pipelineId $PLID '. + {pipelineId: $pipelineId}' > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/pipeline-$PLID.json
	cp $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/pipeline-$PLID.json $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/latest-pipeline-$CURRENT_BUILD_SCLI.json
	#echo -n $EXP_OUTPUT > $CURRENT_BUILD_SCLI/exp-gcs-outputfile.txt
fi
echo "Success: Create Pipeline"
