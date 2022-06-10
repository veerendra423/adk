#!/bin/bash
echo "---------------------------------"
echo "Building Algorithm Docker"
echo "---------------------------------"
pushd ./algorithm > /dev/null
./encrypt_algorithm.sh
popd > /dev/null
cat ../.build-env > .env
source ./.env
cp ./sdata/$CURRENT_BUILD_SCLI/.env .
cat $SCLI_ALGO_DATA/enc-key >> .env 2> /dev/null
#
# Build algorithm image
#
docker-compose build algorithm
MRENCLAVE_ALGORITHM="$(docker-compose run --no-deps -eSCONE_HASH=1 algorithm | tail -1)"
echo -n "MRENCLAVE_ALGORITHM=" >> sdata/$CURRENT_BUILD_SCLI/.env
echo ${MRENCLAVE_ALGORITHM%?} >> sdata/$CURRENT_BUILD_SCLI/.env
#echo SENSDECRYPT_FSPF_KEY=9d64e3a7f0ace811c9de4b1007900c038c7bc72726964b08196790f8e210a669 >> sdata/$SCLI_CURRENT_BUILD/.env
#
# Push image
#
docker-compose push algorithm
