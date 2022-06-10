#!/bin/bash
  
source ./config
pushd /opt/$SBOX_PRODUCT_VERSION/app > /dev/null
./putsboxenv.sh
popd > /dev/null

