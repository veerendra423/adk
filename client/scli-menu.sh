#!/bin/bash 

if test -f "./.build-env"; then
	source ./.build-env 2> /dev/null
fi

if ! test -f "./config"; then
	echo "No config file!! Aborting ..."
	exit 1
fi

source ./config
#RELEASE_TAG=${RELEASE_TAG}
DEV_MODE=true
if [ $DEV_MODE == true ]; then
	SENSEC_IMAGE=dev/scli:ccf2
else
	SENSEC_IMAGE=scli:ccf2
fi

RELEASE_TAG=$SCLI_PRODUCT_VERSION

if [ $PWD != $SCLI_ROOT ]; then
	echo "Please review SCLI_ROOT setting in config file and restart"
	exit 1
fi

if [ -z "$GCS_CREDS_FILE_NAME" ]; then
	echo "Please export GCS_CREDS_FILE_NAME and try again"
	exit 1
fi

if ! test -f "$GCS_CREDS_FILE"; then
	echo $GCS_CREDS_FILE does not exist - try again when you have it
	exit 1

fi

setup_scli()
{
	source ./build-env 2> /dev/null
	source ./config
	echo "Setting Up SCLI..."
	echo "Checking if local client registry is running"
	if [ ! "$(docker ps -aq -f status=running -f name=clientregistry)" ]; then
		echo "	registry not running; starting now"
		docker pull registry:latest
		docker run -d -p 5000:5000 --restart=always --name clientregistry registry
		echo "	registry started"
	else
		echo "	registry ok"
	fi

	if [ $SCLI_USE_REF = "true" ]; then
		if ! test -f $SCLI_REF_ALGO_TAR; then
			./scli.sh sensec \
				mktar \
				-scred $SCLI_REF_ALGO_CREDS \
				-tf $SCLI_REF_ALGO_TAR \
				$SCLI_REF_ALGO_IMAGE
		fi
	fi

	# pull the docker bash image; used for removing root owned files later for cleanup
	docker pull docker.io/library/bash:latest

	if test -f $SCLI_ALGO_DATA/enc-volume.fspf; then
		echo "Using Input DataSet `cat $SCLI_ALGO_DATA/datasets/current_ds.json | jq '.name'`"
	fi

	if [ $SCLI_STANDALONE != true ]; then
	    re_create_dataset
	else
	    echo Skipping encrypt input data in standalone mode
	fi

	echo "Success: Setup SCLI"
    	echo "Done.."
}

re_create_dataset()
{
	if [ $SCLI_STANDALONE == true ]; then
		echo "In Standalone mode ... skipping create input dataset ..."
		echo "Success: Create Input DataSet"
		return
	fi
	if test -f $SCLI_ALGO_DATA/enc-volume.fspf; then
		while true; do
    			read -p "Do you want to re-encrypt the dataset?" yn
    			case $yn in
        			[Yy]* ) break;;
        			[Nn]* ) echo "aborting re-encrypt ... "; 
					return;;
       				* ) echo "Please answer yes or no.";;
    			esac
		done
		rm -f $SCLI_ALGO_DATA/enc-key > /dev/null
		rm -f $SCLI_ALGO_DATA/enc-volume.fspf > /dev/null
	fi

	echo "Encrypting and Pushing Dataset"

	EMPTY_DIR=$SCLI_ALGO_DATA/symkeygen_empty-dir
	EMPTY_OUTDIR=$SCLI_ALGO_DATA/symkeygen_encrypted-output
	mkdir -p $EMPTY_DIR 
	mkdir -p $EMPTY_OUTDIR 
	if [ "$(ls -A $EMPTY_DIR)" ]; then
		echo "Please empty $EMPTY_DIR and try again"
		echo "Failed: Create Input DataSet"
		return
	fi
	if [ "$(ls -A $EMPTY_OUTDIR)" ]; then
		echo "Please empty $EMPTY_OUTDIR and try again"
		echo "Failed: Create Input DataSet"
		return
	fi

	echo Generating Encryption key
	docker run --rm -e HUSER=$(id -u) -e HGRP=$(id -g) -e SCONE_MODE=sim -it -v $EMPTY_DIR:/empty-dir -v $EMPTY_OUTDIR:/encrypted-output sensoriant.azurecr.io/priv-comp/python-3.8.1-ubuntu:11302020 bash -c "
	    	rm -rf /encrypted-output/* && \
    		mkdir -p /encrypted-output && \
    		cd /encrypted-output && \
    		scone fspf create volume.fspf && \
    		scone fspf addr /encrypted-output/volume.fspf . --encrypted --kernel . && \
    		scone fspf addf /encrypted-output/volume.fspf . /empty-dir /encrypted-output/ && \
    		scone fspf encrypt volume.fspf > /empty-dir/tag_key.txt && \
		chown $HUSER:$HGRP /encrypted-output/volume.fspf && \
		chown $HUSER:$HGRP /empty-dir/tag_key.txt && \
    		cat /empty-dir/tag_key.txt" | tail -1

	while IFS= read -r line
	do
 		echo "$line" | awk '{print "SENSENCRYPT_FSPF_KEY="substr($0,102,64)}' > $SCLI_ALGO_DATA/enc-key
	done < "$EMPTY_DIR/tag_key.txt"
	mv $EMPTY_OUTDIR/volume.fspf $SCLI_ALGO_DATA/enc-volume.fspf
	rm -f $EMPTY_DIR/tag_key.txt
	rmdir $EMPTY_DIR 
	rmdir $EMPTY_OUTDIR 

	echo Encrypting DataSet
	#clean up the output directory
	docker run --rm -v $SCLI_ALGO_DATA:/d-inp docker.io/library/bash:latest bash -c 'rm -rf /d-inp/encrypt-output/*' > /dev/null
	cp $SCLI_ALGO_DATA/enc-volume.fspf $SCLI_ALGO_DATA/encrypt-output/volume.fspf
    	echo "Copying input files to SensEncrypt input directory"
    	cp -r $SCLI_ALGO_DATA/algorithm-input/* $SCLI_ALGO_DATA/encrypt-input/
	pushd ./image >> /dev/null
	cp $SCLI_ALGO_DATA/enc-key .env
    	docker-compose run --rm SensEncrypt
	popd >> /dev/null

	echo Pushing Encrypted DataSet to GCS Bucket
	secn=`date +%s`
	bn=`expr $secn - $BASE_BUILD_SCLI`
	DSNAME=Default_DS_$bn
	pushd ./image >> /dev/null
	echo InputDataSetName=$DSNAME > .env
	source .env
	echo "Pushing files to GCS - ${InputDataSetName}"
	docker-compose run --rm -e GCS_OBJECT_PREFIX="${InputDataSetName}" -v $SCLI_ALGO_DATA/encrypt-output:/opt/sensoriant/gcs/push/filesToBucket SensGcsPush
	popd >> /dev/null

	enkey=`awk -F= '$1=="SENSENCRYPT_FSPF_KEY"{print $2}' $SCLI_ALGO_DATA/enc-key`
	cat $SCLI_ALGO_DATA/datasets/${InputDataSetName}.json | sed -e s/\}/,\"SENSENCRYPT_FSPF_KEY\":\"$enkey\"\}/g > t
	mv -f t $SCLI_ALGO_DATA/datasets/${InputDataSetName}.json
	cp $SCLI_ALGO_DATA/datasets/${InputDataSetName}.json $SCLI_ALGO_DATA/datasets/current_ds.json

	echo "Success: Create Input DataSet"
	echo "Using Input DataSet `cat $SCLI_ALGO_DATA/datasets/current_ds.json | jq '.name'`"
    	echo "Done.."
}

switch_build()
{
	echo "Switching Build"
	while true; do
		read -p "Build Number you want to switch to? (number or quit) " bnum
    		case $bnum in
        		[Qq]* ) echo "aborting switch ... "; return;;
       			* ) if [ -d $SCLI_ALGO_DIR/$bnum ]; then
				if test -f "$SCLI_ALGO_DIR/$bnum/.build-env"; then
					cp $SCLI_ALGO_DIR/$bnum/.build-env $SCLI_ROOT/.build-env
					source ./.build-env
					source ./config
					echo "Using Build Number: $CURRENT_BUILD_SCLI"
					echo "Success: Switch Build"
					break
				fi
				
			    fi
			    echo "Please answer with valid build number or quit";;
    		esac
	done
}

show_bnum()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
	else
		echo "Current Build Number is: $CURRENT_BUILD_SCLI"
	fi
}

build_container_image()
{
	if [ ! -z $CURRENT_BUILD_SCLI ]; then
		while true; do
    			read -p "Are you sure you want to create a new build number and switch to it?" yn
    			case $yn in
        			[Yy]* ) break;;
        			[Nn]* ) echo "aborting new build ... "; return;;
       				* ) echo "Please answer yes or no.";;
    			esac
		done
	fi
	echo "Building Container Image"
	pushd ./image > /dev/null
	./build.sh
	popd > /dev/null
	source ./.build-env 2> /dev/null
	source ./config 2> /dev/null
	echo "Success: Build Container Image"

	echo "Generating Output Decryption Key"
	output_symkey_gen
    	echo "Done.."
}

output_symkey_gen()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		echo "Failed: Generate Output Decryption Key"
		return
	fi

  		#rm -rf /encrypted-output/* && \
  		#mkdir -p /encrypted-output && \
	EMPTY_DIR=$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/symkeygen_empty-dir
	EMPTY_OUTDIR=$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/symkeygen_encrypted-output
	mkdir -p $EMPTY_DIR 
	mkdir -p $EMPTY_OUTDIR 
	if [ "$(ls -A $EMPTY_DIR)" ]; then
		echo "Please empty $EMPTY_DIR and try again"
		echo "Failed: Generate Output Decryption Key"
		return
	fi
	if [ "$(ls -A $EMPTY_OUTDIR)" ]; then
		echo "Please empty $EMPTY_OUTDIR and try again"
		echo "Failed: Generate Output Decryption Key"
		return
	fi
	docker run --rm -e HUSER=$(id -u) -e HGRP=$(id -g) -e SCONE_MODE=sim -it -v $EMPTY_DIR:/empty-dir -v $EMPTY_OUTDIR:/encrypted-output sensoriant.azurecr.io/priv-comp/python-3.8.1-ubuntu:11302020 bash -c "
  		cd /encrypted-output && \
  		scone fspf create volume.fspf && \
  		scone fspf addr /encrypted-output/volume.fspf . --encrypted --kernel . && \
  		scone fspf addf /encrypted-output/volume.fspf . /empty-dir /encrypted-output/ && \
  		scone fspf encrypt volume.fspf > /empty-dir/tag_key.txt && \
  		rm -rf /encrypted-output/* && \
		chown $HUSER:$HGRP /empty-dir/tag_key.txt && \
  		cat /empty-dir/tag_key.txt" | tail -1

	while IFS= read -r line
	do
 		echo "$line" | awk '{print "SENSDECRYPT_FSPF_KEY="substr($0,102,64)}' >> $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/.env
	done < "$EMPTY_DIR/tag_key.txt"
	${SUDOCMD} rm -f $EMPTY_DIR/tag_key.txt
	rmdir $EMPTY_DIR 
	rmdir $EMPTY_OUTDIR 

	echo "Success: Generate Output Decryption Key"
    	echo "Done.."
}

run_image_locally()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi

	echo "Run Image Locally"
	pushd ./image > /dev/null
	./run.sh
	popd > /dev/null
    	echo "Done.."
}

run_esig_push()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi

	echo "Encrypt and Sign Image"
	if test -f "$SCLI_SIGNING_KEY"; then
		./scli.sh sensec \
                	esig -sreg $SCLI_REGISTRY \
                -dreg $SCLI_SENSE_REG \
                -dcred $SCLI_SENSE_REG_USER \
                	-dom $SCLI_DOMAIN \
                	-skey $SCLI_SIGNING_KEY \
                	--outdir $SCLI_ALGO_DIR \
			$SCLI_REGISTRY/$SCLI_REPO/$SCLI_IMAGE:${SCLI_TAG}_$CURRENT_BUILD_SCLI
	else
		echo "Missing Signing key!!"
	fi
    	echo "Done.."
}

run_esig()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi

	echo "Encrypt and Sign Image"
	##docker inspect $SCLI_REF_ALGO_IMAGE | jq '.[] | .RootFS.Layers | .[]'
	##docker inspect $unencimage | jq '.[] | .RootFS.Layers | .[]'
	#baselayers=`docker inspect $SCLI_REF_ALGO_IMAGE | jq '.[] | .RootFS.Layers | .[]' | wc -l`
	#unencimage=$SCLI_REGISTRY/$SCLI_REPO/$SCLI_IMAGE:${SCLI_TAG}_$CURRENT_BUILD_SCLI
	#alllayers=`docker inspect $unencimage | jq '.[] | .RootFS.Layers | .[]' | wc -l`
	#topxlayers=`expr $alllayers - $baselayers`
	#echo $topxlayers
	#--topx=$topxlayers $refopt \
	refopt=""
	if [ $SCLI_USE_REF = "true" ]; then
		refopt=" --reftar $SCLI_REF_ALGO_TAR "
	fi
	if test -f "$SCLI_SIGNING_KEY"; then
		./scli.sh sensec \
                	esig -sreg $SCLI_REGISTRY \
                	-dom $SCLI_DOMAIN \
                	-skey $SCLI_SIGNING_KEY \
                	--outdir $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI \
                	--outtar $refopt \
			$SCLI_REGISTRY/$SCLI_REPO/$SCLI_IMAGE:${SCLI_TAG}_$CURRENT_BUILD_SCLI
	else
		echo "Missing Signing key!!"
	fi
    	echo "Done.."
}

run_import_tar()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi

	echo "Submit Image tar"
	if [ $SCLI_STANDALONE == true ]; then
		refopt=""
		if [ $SCLI_USE_REF = "true" ]; then
			refopt=" --reftar $SCLI_REF_ALGO_TAR "
		fi
		./scli.sh sensec sctr import \
                	--imagetar $SCLI_IMAGE_TAR_FILE \
               		-dreg $SCLI_SENSE_REG \
               		-dcred $SCLI_SENSE_REG_USER $refopt
	else
		#pushing to google bucket
		echo "Pushing tarfile  to Google bucket"
		#./scli.sh sensec gbp -it $SCLI_IMAGE_TAR_FILE --od $SCLI_ALGO_DIR
		./scli.sh sensec gbp -it $SCLI_IMAGE_TAR_FILE --od $SCLI_ALGO_DIR --bn $GCS_ALGO_STORAGE_BUCKET

		echo "Submit Algorithm to API Server"
		SCLI_DIGEST=$( cat $SCLI_MEAS_FILE | sed -e s/sha256:// )
        	algoret=`curl -s -w "%{http_code}" --keepalive-time 30  --connect-timeout 500  --insecure -X POST "https://$SCLI_API_SERVER/secure_cloud_api/v1/algorithms" -H  "accept: application/json" -H  "Content-Type: application/json" -d "{\"storageProvider\":\"GCS\",\"bucketName\":\"$GCS_ALGO_STORAGE_BUCKET\",\"objectName\":\"$SCLI_IMAGE_TAR\",\"digest\":\"$SCLI_DIGEST\"}"`
		if [ ! `echo $algoret | tail -c 4` == "201" ]; then
        		echo $algoret
        		echo "Failed: Submit Algorithm"
        		return
		fi
		echo ${algoret%???} > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/algo.json
		algoid=`cat $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/algo.json | jq -r '.id'`
		echo Algorithm Id is: $algoid
        	echo "Success: Submit Algorithm"
	fi 
    	echo "Done.."
}

create_platform()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi

	echo "Create Platform"
	if [ $SCLI_STANDALONE == true ]; then
		echo Will use default platform key
		cp $SCLI_DEFAULT_MACHINE_KEY $SCLI_MACHINE_KEY
		# Create mock secure stream platform info
		echo "{
  		\"name\": \"DefaultSSP_$CURRENT_BUILD_SCLI\",
  		\"id\": \"$CURRENT_BUILD_SCLI\",
  		\"measurement\": \"`echo defaultmeasurement | base64 -w0 `\"
		}" > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/ssp.json
	else
		if test -f "$SCLI_MACHINE_KEY"; then
			rm $SCLI_MACHINE_KEY
		fi
        
		sspret=`curl -s -w "%{http_code}" --connect-timeout 500  --insecure -X GET "https://$SCLI_API_SERVER/secure_cloud_api/v1/secure_stream_platforms?limit=10&skip=0" -H  "accept: application/json"`
		if [ ! `echo $sspret | tail -c 4` == "200" ]; then
        		echo $sspret
        		echo "Failed: Get Platform"
        		return
		else
			# check if there are more than 0 platforms
			sspfound=`echo ${sspret%???} | jq '.found'`
			if [ $sspfound == 0 ]; then
				echo ${sspret%???}
        			echo "Failed: Get Platform"
			fi
		fi
		#PUBKEY=`cat $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/ssp.json | jq '.publicKey'`
		PUBKEY=`echo ${sspret%???} | jq '.secureStreamPlatforms[0].publicKey'`
		GOT_MKEY=`echo $PUBKEY | grep PUBLIC`
        	if [ ! -z "$GOT_MKEY" ]; then
                	echo $PUBKEY | sed -e s/\"//g | awk '{gsub(/\\n/,"\n")}1' > $SCLI_MACHINE_KEY
		else
			echo "Invalid Public Key"
			echo $PUBKEY
        	fi
		echo ${sspret%???} | jq '.secureStreamPlatforms[0]' > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/ssp.json
        fi

	if test -f "$SCLI_MACHINE_KEY"; then
		echo "Platform key obtained"
        	echo "Success: Get Platform"
	else
		echo "Missing platform key!!"
        	echo "Failed: Get Platform"
	fi
    	echo "Done.."
}

push_dataset_keys()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
        	echo "Failed: Push DataSet Key"
		return
	fi

	SSPFile=$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/ssp.json
	if ! test -f $SSPFile; then
		echo "Create platform and try again ... "
        	echo "Failed: Push DataSet Key"
		return
	fi

	DSFile=$SCLI_ALGO_DATA/datasets/current_ds.json
	if ! test -f $DSFile; then
		echo "No encrypted dataset is present ... "
        	echo "Failed: Push DataSet Key"
		return
	fi

	echo "Creating DataSet key"
	awk -F= '$1=="FSPF_KEY"{print $2}' $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/.env 
	cat $DSFile | jq -r '.SENSENCRYPT_FSPF_KEY' > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dsk.encryptedSymmetricKey
	./scli.sh sensec \
                        ek \
                        --blob $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dsk.encryptedSymmetricKey  \
                        --mpk $SCLI_MACHINE_KEY \
                        --outdir $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI
	dsname=`cat $DSFile | jq -r '.name'`
	ensymk=\"`base64 -w0 $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dsk.encryptedSymmetricKey-eb`\"
	echo "{
	    \"name\": \"${dsname}_${CURRENT_BUILD_SCLI}-Key\",
  	    \"encryptedSymmetricKey\": $ensymk,
  	    \"secureStreamPlatform\": {
	        \"name\": $(cat $SSPFile | jq '.name'),
    	        \"id\": $(cat $SSPFile | jq '.id')
  	    },
  	    \"dataset\": {
	        \"name\": $(cat $DSFile | jq '.name'),
    	        \"id\": $(cat $DSFile | jq '.id')
  	    }
	}" > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dskreq.json

	if [ $SCLI_STANDALONE == true ]; then
		echo "In standalone mode ... skipping upload to api server"
	else
		echo Uploading DataSet Key to API Server
		dskj=`cat $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dskreq.json`
		dskret=`curl -s -w "%{http_code}" --keepalive-time 30  --connect-timeout 500  --insecure -X POST "https://$SCLI_API_SERVER/secure_cloud_api/v1/datasets/keys" -H  "accept: application/json" -H  "Content-Type: application/json" -d "$dskj"`
		if [ ! `echo $dskret | tail -c 4` == "201" ]; then
        		echo $dskret
        		echo "Failed: Push DataSet Key"
        		return
		fi
	        echo ${dskret%???} > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dsk.json
		SELDSK=`cat $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dsk.json | jq '.id'`
		echo Selected DataSet: "$SELDSK"
		rm -f $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dskreq.json
	fi

        echo "Success: Push DataSet Key"
	echo "Done.."
}

get_dataset_keys()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi
	if [ $SCLI_STANDALONE == true ]; then
		echo "In Standalone mode ... using default ..."
        	echo "Success: Get DataSet Key"
		return
	fi
 
	if test -f $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/ssp.json; then
		SENSESSPID=`cat $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/ssp.json | jq -r '.id'`
		sspdskret=`curl -s -w "%{http_code}" --connect-timeout 500  --insecure -X GET "https://$SCLI_API_SERVER/secure_cloud_api/v1/datasets/keys/by_platform_id/$SENSESSPID?limit=10&skip=0" -H  "accept: application/json"`
		if [ ! `echo $sspdskret | tail -c 4` == "200" ]; then
        		echo $ssdskpret
        		echo "Failed: Get DataSet Key"
        		return
		else
			# check if there are more than 0 platforms
			sspfound=`echo ${sspdskret%???} | jq '.found'`
			if [ $sspfound == 0 ]; then
				echo ${sspdskret%???}
        			echo "Failed: Get DataSet Key"
			fi
		fi
	        echo ${sspdskret%???} | jq '.datasetKeys[0]' > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dsk.json
		SELDSK=`cat $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/dsk.json | jq '.name'`
		echo Selected DataSet Key: "$SELDSK"
	else
        	echo "Failed: Get DataSet Key"
		echo "Did you create platform? Try again ..."
	fi

        echo "Success: Get DataSet Key"
	echo "Done ..."
}

submit_pipeline()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi

	echo "Creating Pipeline .."
	pushd $SCLI_ALGO_DIR > /dev/null
	./submitjson.sh
	popd > /dev/null
    	echo "Done.."
}

create_pipeline()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi

	echo "Create Pipeline"
	echo "Encrypting Image private key"
	./scli.sh sensec \
                        ek \
                        --ipk $SCLI_IPK_FILE \
                        --mpk $SCLI_MACHINE_KEY \
                        --outdir $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI

	echo "Encrypting Algorithm FSPF key"
	awk -F= '$1=="FSPF_KEY"{print $2}' $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/.env > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/algorithm.decryptionKeys.enclave.decryptionKey
	./scli.sh sensec \
                        ek \
                        --blob $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/algorithm.decryptionKeys.enclave.decryptionKey  \
                        --mpk $SCLI_MACHINE_KEY \
                        --outdir $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI

	echo "Encrypting Output Sym key"
	awk -F= '$1=="SENSDECRYPT_FSPF_KEY"{print $2}' $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/.env > $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/output.encryptionkey.symmetrickey
	./scli.sh sensec \
                        ek \
                        --blob $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/output.encryptionkey.symmetrickey  \
                        --mpk $SCLI_MACHINE_KEY \
                        --outdir $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI

	submit_pipeline
	echo "Done.."
}

start_pipeline()
{
	if [ $SCLI_STANDALONE == true ]; then
		echo "In Standalone mode ... feature not available..."
		echo "Success: Start Pipleline"
		return
	fi
 
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi

	cpl=$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/latest-pipeline-$CURRENT_BUILD_SCLI.json
	plid=`cat $cpl | jq -r '.pipelineId'`

	plinfo=`curl  -s -w "%{http_code}" --keepalive-time 30  --connect-timeout 500  --insecure -X POST "https://$SCLI_API_SERVER/secure_cloud_api/v1/pipelines/start/$plid" -H  "accept: application/json" -d ""`

	if [ ! `echo $plinfo | tail -c 4` == "200" ]; then
		echo "Start Pipeline failed ..."
		echo $plinfo
		echo "Failed: Start Pipleline"
		return 1
	else
		echo "Pipeline started ..."
	fi

	echo "Success: Start Pipleline"
	echo "Done.."
}

pull_decrypt_output()
{
	if [ $SCLI_STANDALONE == true ]; then
		echo "In Standalone mode ... nothing to pull and decrypt ..."
		return
	fi
 
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi

	cpl=$SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/latest-pipeline-$CURRENT_BUILD_SCLI.json
	if ! test -f "$cpl"; then
		echo "Try again after you create and submit pipeline ..."
		return
	fi

	./fetch_output.sh $cpl
}

delete_build()
{
	if [ -z $CURRENT_BUILD_SCLI ]; then
		echo "Build number not available!!"
		return
	fi

	echo "Deleting Build"
	while true; do
    		read -p "Are you sure you want to discard build number $CURRENT_BUILD_SCLI?" yn
    		case $yn in
        		[Yy]* ) break;;
        		[Nn]* ) echo "aborting reset ... "; return;;
       			* ) echo "Please answer yes or no.";;
    		esac
	done

	if test -f "$SCLI_ROOT/.build-env"; then
		rm -f $SCLI_ROOT/.build-env
	fi

	if test -f "$SCLI_ROOT/image/.env"; then
		rm -f $SCLI_ROOT/.env
	fi

	if [ -d $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI ]; then
		#${SUDOCMD} rm -rf $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI
		docker run --rm -e cn=${CURRENT_BUILD_SCLI} -v $SCLI_ALGO_DIR:/d-inp docker.io/library/bash:latest bash -c 'rm -rf /d-inp/${cn}' > /dev/null
	fi

	unset CURRENT_BUILD_SCLI

	#${SUDOCMD} rm -rf $SCLI_ROOT/image/algorithm/image_files > /dev/null
	docker run --rm -v $SCLI_ROOT:/d-inp docker.io/library/bash:latest bash -c 'rm -rf /d-inp/image/algorithm/image_files' > /dev/null
	#${SUDOCMD} rm -rf $SCLI_ALGO_DATA/algorithm-output/* > /dev/null
	docker run --rm -v $SCLI_ALGO_DATA:/d-inp docker.io/library/bash:latest bash -c 'rm -rf /d-inp/algorithm-output/*' > /dev/null
}

#reset_container_encryption()
#{
#	if [ -z $CURRENT_BUILD_SCLI ]; then
#		echo "Build number not available!!"
#		return
#	fi
#
#	rm -f $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/*.pem
#	${SUDOCMD} rm -f $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/*.pem-ek
#	rm -f $SCLI_ALGO_DIR/$CURRENT_BUILD_SCLI/*.tar
#
#}
#
#reset()
#{
#    echo "In reset()"
#    echo "Reset Algorithm and SCLI"
#    reset_algorithm
#    echo "Done.."
#}

show_header()
{
    echo "-------------------------------------------"
    echo "Build# (Standalone): $CURRENT_BUILD_SCLI ($SCLI_STANDALONE)"
    echo "-------------------------------------------"
}

show_options()
{
    echo "-------------------------------------------"
    echo "Sensoriant Release: $RELEASE_TAG" 
    echo "Build# (Standalone): $CURRENT_BUILD_SCLI ($SCLI_STANDALONE)"
    echo "-------------------------------------------"
    PS3='Please enter your choice: '
options=("Setup SCLI" "ReEncrypt DataSet" "Switch to Another Existing Build" "Build New Image and Gen Algo Keys" "Run Image Locally" "Encrypt and Sign Image" "Submit Image tar" "Create Platform" "Create and Upload DataSet Keys" "Create and Submit Pipeline" "Start Pipeline" "Fetch and Decrypt Output" "Delete Build" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Setup SCLI")
             echo "Setting Up SCLI"; setup_scli; show_header
             ;;
            "ReEncrypt DataSet")
             echo "ReEncrypting DataSet"; re_create_dataset; show_header
             ;;
            #"Show Current Build Number")
            # echo "Looking for current build number"; show_bnum; show_header
            # ;;
            "Switch to Another Existing Build")
             echo "Switch to Another Existing Build"; switch_build; show_header
             ;;
            "Build New Image and Gen Algo Keys")
             echo "Building New Container Image"; build_container_image; show_header
             ;;
            "Run Image Locally")
             echo "Run Image Locally"; run_image_locally; show_header
             ;;
            "Encrypt and Sign Image")
             echo "Encrypt and Sign Image"; run_esig; show_header
             ;;
            "Submit Image tar")
             echo "Submitting Image tar"; run_import_tar; show_header
             ;;
            "Create Platform")
             echo "Creating Platform"; create_platform; show_header
             ;;
            "Create and Upload DataSet Keys")
             echo "Creating DataSet Keys"; push_dataset_keys; show_header
             ;;
            "Create and Submit Pipeline")
             echo "Creating Pipeline"; create_pipeline; show_header
             ;;
     	    "Start Pipeline")
	     echo "Starting Pipeline..."; start_pipeline; show_header
	     ;;
     	    "Fetch and Decrypt Output")
	     echo "Fetch and Decrypt Output"; pull_decrypt_output; show_header
	     ;;
            "Delete Build")
             echo "Delete Build"; delete_build; show_header
             ;;
            #"Reset Container Encryption")
            # echo "Reset Container Encryption"; reset_container_encryption; show_header
            # ;;
            "Quit")
		break
                ;;
            *)
	    show_header
            PS3="" # this hides the prompt
                echo asdf | select foo in "${options[@]}"; do break; done; # dummy select
                PS3="Please enter your choice: " # this displays the common prompt
                ;;
        esac
    done
}

show_options
