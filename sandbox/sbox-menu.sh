#!/bin/bash 
if test -f "./config"; then
        echo "Using existing config file ..."
        echo "Please remove ./config if you want to reparse pipeline ..."
        sleep 2
else
        if test -f "./pipeline.json"; then
                if test -f "./config"; then
                        rm ./config
                fi
                echo "Generating config"
                ./genconfig.sh ./pipeline.json
        else
                echo "No pipeline to exec"
                exit 1
        fi
fi

if test -f "./config"; then
	echo "Starting ..."
else
	echo "No config file!! Make sure you submit pipeline from Client..."
	echo "Aborting ..."
	exit 1
fi

source ./config
#RELEASE_TAG=${RELEASE_TAG}
DEV_MODE=true
if [ $DEV_MODE == true ]; then
	SENSEC_IMAGE=dev/scli:latest
else
	SENSEC_IMAGE=scli:latest
fi

RELEASE_TAG=1.0.x

if [ $PWD != $SBOX_ROOT ]; then
	echo "Please review your config file and restart"
	exit 1
fi

if [ -z $CURRENT_BUILD_SBOX ]; then
	echo "No build number! Please resubmit properly from client and try again!"
	echo "Aborting ..."
	exit 1
fi

#if [ ! -d $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX ]; then
#	echo "No build number contents! Please resubmit properly from client and try again!"
#	echo "Aborting ..."
#	exit 1
#fi

echo "Checking product version"
if [ -z "$SBOX_PRODUCT_VERSION" ]; then
        echo "Product version not defined"
        exit 1
fi


echo "Starting sandbox menu for build number: $CURRENT_BUILD_SBOX"
sleep 2

#echo "If you got an error message, make sure you are logged into Sensoriant registry and retry"
setup_sbox()
{
	source ./config
	echo "Setting Up Sandbox..."
	echo "Checking product version"
	if [ -z "$SBOX_PRODUCT_VERSION" ]; then 
		echo "Product version not defined"
		exit 1
	fi
	echo "Checking if local sandbox registry is running"
	if [ ! "$(docker ps -aq -f status=running -f name=sboxregistry)" ]; then
		echo "	registry not running; starting now"
		docker pull registry:latest
		docker run -d -p 6000:5000 --restart=always --name sboxregistry registry
		echo "	registry started"
	else
		echo "	registry ok"
	fi

    	echo "Done.."
}

verify_measurement()
{
	echo "Verifying Image Measurement"
	./sbox.sh sensec sctr \
                vmeas \
                -sreg $SBOX_SENSE_REG \
                -scred $SBOX_SENSE_REG_USER \
                -meas $SBOX_MEAS_FILE \
		$SBOX_IMAGE_FULLNAME
	rc=$?
	if [ $rc -ne 0 ]; then
		exit $rc
	fi
    	echo "Done.."
}

prepare_pipeline()
{
	echo "Preparing pipeline"
	while true; do
    		read -p "Did you Submit Pipeline from the client menu?" yn
    		case $yn in
        		[Yy]* ) break;;
        		[Nn]* ) echo "Please submit and try again"; break;;
        		* ) echo "Please answer yes or no.";;
    		esac
	done
    	echo "Done.."
}

decrypt_standalone()
{
	if ! test -f "$SBOX_MACHINE_KEY"; then
		echo "Missing platform key!!"
		return
	fi

	echo "Decrypting Image Private Key"
        ./sbox.sh sensec sctr dk -epk $SBOX_EPK_FILE -mpk $SBOX_MACHINE_KEY --outdir $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX
	rc=$?
	if [ $rc -ne 0 ]; then
		exit $rc
	fi

        echo "Decrypting Algorithm decryption Keys"
        ./sbox.sh sensec sctr dk -eb $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/algorithm.decryptionKeys.enclave.decryptionKey-eb -mpk $SBOX_MACHINE_KEY --outdir $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX
	rc=$?
	if [ $rc -ne 0 ]; then
		exit $rc
	fi
	echo -n "FSPF_KEY=" >> $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env
	cat $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/algorithm.decryptionKeys.enclave.decryptionKey-eb-db >> $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env

        echo "Decrypting Output decryption Keys"
        ./sbox.sh sensec sctr dk -eb $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/output.encryptionkey.symmetrickey-eb -mpk $SBOX_MACHINE_KEY --outdir $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX
	rc=$?
	if [ $rc -ne 0 ]; then
		exit $rc
	fi
	echo -n "SENSDECRYPT_FSPF_KEY=" >> $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env
	cat $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/output.encryptionkey.symmetrickey-eb-db >> $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env

        echo "Decrypting DataSet decryption Keys ... TBD"
    	echo "Done.."
}

decrypt_ipk()
{
	if [ $SBOX_STANDALONE == true ]; then
		decrypt_standalone
		return
	fi

	echo "Decrypting Image Private Key"
        ESK=`cat $SBOX_EPK_FILE | jq -r '.EncSymKey'`
        DSK=`docker-compose -f /opt/$SBOX_PRODUCT_VERSION/app/operator/docker-compose.yml --project-directory /opt/$SBOX_PRODUCT_VERSION/app/operator run SensLAS /SensAttest/SensAttest -sha256 -keyHandleId=0 -encryptedData=$ESK -api Decrypt | jq -r '.decryptedText'`
        if [ ! -z "$DSK" ]; then
            ./sbox.sh sensec sctr dk -epk $SBOX_EPK_FILE -sk $DSK --outdir $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX
	    rc=$?
	    if [ $rc -ne 0 ]; then
		    exit $rc
	    fi
        else
            echo "Image Private Key decryption failed"
	    exit 1
        fi

        echo "Decrypting Algorithm decryption Keys"
        ESK=`cat $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/algorithm.decryptionKeys.enclave.decryptionKey-eb | jq -r '.EncSymKey'`
        DSK=`docker-compose -f /opt/$SBOX_PRODUCT_VERSION/app/operator/docker-compose.yml --project-directory /opt/$SBOX_PRODUCT_VERSION/app/operator run SensLAS /SensAttest/SensAttest -sha256 -keyHandleId=0 -encryptedData=$ESK -api Decrypt | jq -r '.decryptedText'`
        if [ ! -z "$DSK" ]; then
            ./sbox.sh sensec sctr dk -eb $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/algorithm.decryptionKeys.enclave.decryptionKey-eb -sk $DSK --outdir $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX
	    rc=$?
	    if [ $rc -ne 0 ]; then
		    exit $rc
	    fi
	    echo -n FSPF_KEY= >> $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env
	    echo `cat $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/algorithm.decryptionKeys.enclave.decryptionKey-eb-db` >> $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env
        else
            echo "Decrypting Algorithm Decryption Key failed"
	    exit 1
        fi

        echo "Decrypting Output decryption Keys"
        ESK=`cat $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/output.encryptionkey.symmetrickey-eb | jq -r '.EncSymKey'`
        DSK=`docker-compose -f /opt/$SBOX_PRODUCT_VERSION/app/operator/docker-compose.yml --project-directory /opt/$SBOX_PRODUCT_VERSION/app/operator run SensLAS /SensAttest/SensAttest -sha256 -keyHandleId=0 -encryptedData=$ESK -api Decrypt | jq -r '.decryptedText'`
        if [ ! -z "$DSK" ]; then
            ./sbox.sh sensec sctr dk -eb $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/output.encryptionkey.symmetrickey-eb -sk $DSK --outdir $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX
	    rc=$?
	    if [ $rc -ne 0 ]; then
		    exit $rc
	    fi
	    echo -n SENSDECRYPT_FSPF_KEY= >> $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env
	    echo `cat $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/output.encryptionkey.symmetrickey-eb-db` >> $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env
	else
            	echo "Decrypting Output Decryption Key failed"
		exit 1
    	fi

        echo "Decrypting DataSet decryption Keys"
        ESK=`cat $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/dataset.decryptionkey.symmetrickey-eb | jq -r '.EncSymKey'`
        DSK=`docker-compose -f /opt/$SBOX_PRODUCT_VERSION/app/operator/docker-compose.yml --project-directory /opt/$SBOX_PRODUCT_VERSION/app/operator run SensLAS /SensAttest/SensAttest -sha256 -keyHandleId=0 -encryptedData=$ESK -api Decrypt | jq -r '.decryptedText'`
        if [ ! -z "$DSK" ]; then
            ./sbox.sh sensec sctr dk -eb $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/dataset.decryptionkey.symmetrickey-eb -sk $DSK --outdir $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX
	    rc=$?
	    if [ $rc -ne 0 ]; then
		    exit $rc
	    fi
	    echo -n SENSENCRYPT_FSPF_KEY= >> $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env
	    echo `cat $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/dataset.decryptionkey.symmetrickey-eb-db` >> $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX/.env
	else
            	echo "Decrypting DataSet Decryption Key failed"
		exit 1
    	fi
    	echo "Done.."
}

decrypt_image()
{
	echo "Verifying Image Signature and Decrypting it.."
	./sbox.sh sensec sctr \
		vdec \
                -sreg $SBOX_SENSE_REG \
                -scred $SBOX_SENSE_REG_USER \
		-dkey $SBOX_DK_FILE \
		--dom $SBOX_DOMAIN \
		--dreg $SBOX_REGISTRY \
		--vkey $SBOX_VERIFICATION_KEY \
		$SBOX_IMAGE_FULLNAME
	rc=$?
	if [ $rc -ne 0 ]; then
		exit $rc
	fi
    	echo "Done.."
}

run_image()
{
	echo "Run Image"
	if [ $SBOX_STANDALONE == true ]; then
		pushd ./image > /dev/null
		./run.sh
		popd > /dev/null
	else
		./runproductsandbox.sh 
		#pushd $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX  > /dev/null
		##massage the product version VERSION_ to become v
        	#cp .env /opt/$SBOX_PRODUCT_VERSION/app/keys/algorithm/
		#echo ALGORITHM_IMAGE=$UNENC >> /opt/$SBOX_PRODUCT_VERSION/app/.env
		##echo "ALGORITHM_IMAGE=${SBOX_REGISTRY}/${SBOX_REPO}/${SBOX_IMAGE}" >> /opt/$SBOX_PRODUCT_VERSION/app/.env
        	##echo "ALGORITHM_TAG=${SBOX_TAG}_${CURRENT_BUILD_SCLI}" >> /opt/$SBOX_PRODUCT_VERSION/app/.env
	fi
    	echo "Done.."
}


reset_sandbox()
{
	echo "Reset Sandbox and Exit"
	if test -f "$SBOX_ROOT/config"; then
		rm -f $SBOX_ROOT/config
	fi

	if [ -d $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX ]; then
		#sudo rm -rf $SBOX_ALGO_DIR/$CURRENT_BUILD_SBOX
		docker run --rm -e cn=${CURRENT_BUILD_SBOX} -v $SCLI_ALGO_DIR:/d-inp docker.io/library/bash:latest bash -c 'rm -rf /d-inp/${cn}' > /dev/null
	fi

	unset CURRENT_BUILD_SBOX
	echo "Reset Sandbox ... Done .."
	exit 0

}

reset()
{
    echo "In reset()"
    echo "Reset Algorithm and SBOX"
    reset_algorithm
    echo "Done.."
}

run_all()
{
	setup_sbox
	verify_measurement
	decrypt_ipk
	decrypt_image
	run_image
}

show_options()
{
    echo "-------------------------------------------"
    echo "Sensoriant Sandbox Release: $SBOX_PRODUCT_VERSION" 
    echo "-------------------------------------------"
    PS3='Please enter your choice: '
options=("Setup Sandbox" "Verify Image Measurement" "Decrypt Algo Image and DataSet Keys" "Verify Signature and Decrypt Image" "Run Image" "Run all"  "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Setup Sandbox")
             echo "Setting Up Sandbox"; setup_sbox
             ;;
            "Verify Image Measurement")
             echo "Verifying Image Measurement"; verify_measurement
             ;;
            "Decrypt Algo Image and DataSet Keys")
             echo "Decrypting Keys"; decrypt_ipk
             ;;
            "Verify Signature and Decrypt Image")
             echo "Verifying Signature and Decrypting Image"; decrypt_image
             ;;
            "Run Image")
             echo "Running Image"; run_image
             ;;
            "Run all")
             echo "Running Image"; run_all
	     break
             ;;
            #"Reset Sandbox and Exit")
            # echo "Reset Sandbox and Exit"; reset_sandbox
            # ;;
            "Quit")
                break
                ;;
            *)
            PS3="" # this hides the prompt
                echo asdf | select foo in "${options[@]}"; do break; done # dummy select
                PS3="Please enter your choice: " # this displays the common prompt
                ;;
        esac
    done
}

show_options
