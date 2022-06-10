#!/bin/bash 
#
# Temporary to get the algorithm keys
# Normally these keys will be in the algorithm policy
#
cp sdata/$CURRENT_BUILD_SBOX/.env .env
lines=`wc -l .env | awk '{print $1}'`
if [ $lines -lt 2 ]; then
	echo "Please decrypt keys from menu and try again"
	rm -f .env
	exit 1
fi
echo "---------------------------------"
echo "Running Algorithm"
echo "---------------------------------"
#docker-compose pull algorithm
./get_image.sh
docker-compose run algorithm
rm -f .env
