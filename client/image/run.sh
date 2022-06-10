#!/bin/bash
echo "---------------------------------"
echo "Running Algorithm"
echo "---------------------------------"
sudo rm -rf ./volumes/algorithm-output
sudo mkdir -p ./volumes/algorithm-output
cp ./sdata/$CURRENT_BUILD_SCLI/.env .
docker-compose run algorithm
