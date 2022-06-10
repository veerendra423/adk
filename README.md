# Algorithm Development Kit
Algorithm Development kit (ADK) contains a simple template that includes client/developer menu to create an encrypted algorithm and a corresponding signed and encrypted container image. It also includes a sandbox menu to verify, decrypt and run the container image created by the client.

## Basic Structure
The structure of a template named "adk" is shown below.
```sh
adk
├── client
│   └── image
│       ├── algorithm
│       │   ├── app
│       │   └── image_files
│       │       └── app
│       ├── sdata
│       │   ├── 418241
│       │   ├── 418620
│       │   ├── 419236
│       │   ├── 419468
│       │   ├── 493828
│       │   ├── 589331
│       │   ├── 826147
│       │   ├── 827505
│       │   └── 829740
│       └── volumes
│           ├── algorithm-input
│           ├── algorithm-output
│           ├── datasets
│           ├── decrypt-input
│           ├── decrypt-output
│           ├── encrypt-input
│           └── encrypt-output
└── sandbox
    └── image
        ├── sdata
        │   └── default
        └── volumes
            ├── algorithm-input
            └── algorithm-output

``` 
The python files used by the algorithm are located at sample/client/image/algorithm/app. An example app is included and can be modified as appropriate.
```sh
> ls sample/client/image/algorithm/app/
ml_algorithm.py  requirements.txt
>
```
The numbered directories under sdata are build directories and are explained further below.

## Overall Workflow
The client and sandbox are two main components of this template. In addition, there is a central container registry that stores all the encrypted images (docker registry). The *client* facilitates the creation of a *pipeline* object, a Sensoriant construct that comprises of the various elements required to run an algorithm using specified datasets and genarating corresponding output data. The *sandbox* is where this pipeline object is used to perform the run while satisfying required security properties. Essentially, the client creates the pipeline object and hands it over to the sandbox, where the sandbox uses this pipeline object to run this in a secure manner.

Two modes of operation are supported in the ADK
* Standalone mode
* API mode

### Standalone Mode
In this mode, the client and sandbox can be run on a local development machine with the only external dependency being the central container registry. On the client, when an image is first built, it is pushed into a local registry, localhost:5000. Algorithm related keys are generated as part of building the container image. Subsequent options in the client menu pull this image from the local registry, encrypt and sign the image, and then push it to the central container registry. For image encryption, decryption, signing, and verification, the client and sandbox use RSA keys prepopulated in the ADK template. Upon creation of a pipeline object at the client, the client places the pipeline object in the sandbox so further processing can occur using the sandbox menu.

The sandbox menu options provide the workflow to first extracting and decrypting the necessary information from the pipeline object. The pipeline object contains information about the container image that contains the algorithm to be run. The sandbox interacts with the central container registry directly to get this image. The image is first pulled from the central registry, and after verification of measurement and signatures, is decrypted. The decrypted image is pushed into a different local registry, localhost:6000. To run the decrypted image, it is pulled from localhost:6000 and run.

Input and output data encryption and decryption is disabled in standalone mode.

### API mode
In the API mode, an API server that is a component of the Sensoriant Controller, plays a significant role in enabling the functionality of the client and sandbox. The API server provides information about the sandbox platform, including associated public keys; and also provides the facility to exchange encrypted keys between client and sandbox for decryption of input dataset at the sanbox and output dataset at the client. Furthermore, the API server provides the facility to transfer a pipeline object to a specific sandbox and to trigger its run on the specified sandbox.

Pushing the container image for the algorithm is done differently than in the standalone mode. It follows a two step process. The container image is first encrypted and signed and a tarfile containing this encrypted and signed image is produced and is pushed to a storage facility (GCS - Google Cloud Storage, in the current release). The information about the location of the tarfile is then provided to the API server which then performs the task of fetching the tarfile from the specified location, transforming it back to a proper container image format, and pushing it the specified central container registry.

## Client
### Initialization
When starting working on an algorithm, the "config" file in the client directory needs to be updated. The part of the contents that need to be updated are shown below
```sh
> cat sample/client/config 

# Change the following as needed
export SCLI_STANDALONE=false
export SCLI_API_SERVER=<ip-address or FQDN of the api server>
export ROOT_SCLI=$HOME/adk/client
export SCLI_REPO=sensetest
export SCLI_IMAGE=testimagev1
export SCLI_TAG=testv1
export BASE_BUILD_SCLI=`date -d "Jan 09 2021" +%s`

    # the following file for Google storage access must be placed in $SCLI_ALGO_DIR (see below for path)
export GCS_CREDS_FILE_NAME=gcscreds.json
export GCS_ALGO_STORAGE_BUCKET=sensoriant-dev-storage
export GCS_DATA_STORAGE_BUCKET=sensoriant-dev-storage

# Change the following only if you are using a different central container registry; username:password required
export SCLI_SENSE_REG=nferalgos.azurecr.io
export SCLI_SENSE_REG_USER=<username>:<password>

# Change the following as needed for reference image related aspects
export SCLI_USE_REF=true
export SCLI_REF_ALGO_IMAGE=sensoriant.azurecr.io/priv-comp/sensrefimage:11302020
export SCLI_REF_ALGO_CREDS=<username>:<password>

...

```
SCLI_STANDALONE should be set to *true* for standalone mode. The root, repo, image and tag names are to be set according to the template location and the desired characteristics of the container image to be created. BASE_BUILD_SCLI is used in generating "build numbers" and can be set to the date prior to the date when the template is being created or an earlier date; once set, it is recommended that this is not changed again. Each time a new build is created, a new build number is generated. All the encryption related data(e.g measurements, keys etc.) specific to this build is stored in client/image/sdata in a directory whose name is the build number. In the example template structure shown above, 418241 and 418620 are example build numbers created at the client. The image created will be named as repo/image:tag_buildnumber. The use of SCLI_USE_REF will be discussed later below.

The client needs a key for signing the container image, and also a machine(platform) key that is used to encrypt the image decryption key before creating and submitting a pipeline. These keys are named pharma-priv.pem and machine-pub.pem, respectively and located at client/image/sdata. These keys are common across all build numbers. The corresponding pharma-pub.pem and machine-priv.pem are located at sandbox/image/sdata. The pharma and machine keys are part of the template. One may choose to change these keys, but it is required to keep the names of the pem files to be same as in the template.

client/image/volumes/algorithm-input contains sample unencrypted input data for the algorithm. If the algorithm is run locally at the client, the output generated is in client/image/volumes/algorithm-output. client/image/volumes/encrypt-input and client/image/volumes/encrypt-output are directories used to encrypt input datasets. For example, to create an encrypted dataset for the sample input, the contents of client/image/volumes/algorithm-input are copied to client/image/volumes/encrypt-input and the encrypted data is placed in client/image/volumes/encrypt-output. The contents of client/image/volumes/encrypt-output are pushed to a GCS bucket and the information about that is placed in client/image/volumes/datasets - this information includes the dataset name, id as well as the encryption key used; this information is used in creating a pipeline object.

client/image/volumes/decrypt-input is used to place the encrypted output data of a pipeline run, and the decrypted data is placed in client/image/volumes/decrypt-output.

### Invoking the Client Menu
To invoke the client menu, change directory into sample/client and run the scli-menu.sh script.
```sh
> cd $HOME/adk/client
> ./scli-menu.sh 
-------------------------------------------
Sensoriant Release: VERSION_1_1_0
Build# (Standalone): 829740 (false)
-------------------------------------------
1) Setup SCLI                           8) Create Platform
2) ReEncrypt DataSet                    9) Create and Upload DataSet Keys
3) Switch to Another Existing Build    10) Create and Submit Pipeline
4) Build New Image and Gen Algo Keys   11) Start Pipeline
5) Run Image Locally                   12) Fetch and Decrypt Output
6) Encrypt and Sign Image              13) Delete Build
7) Submit Image tar                    14) Quit
Please enter your choice: 

```
Option 1, Setup SCLI must be selected before anything else the first time the menu is invoked. While it is not required to do this again, it doesn't hurt to do this each time scli-menu.sh is started. The sample input is encrypted as part of the processing for option 1. Option 2 can be used to re-encrypt the sample input data if needed for some reason. Options 3 and 4 are for getting current build number, if available, and for switching to another build. Both of these options wouldn't be relevant before container images are built at least once.

To create a new build, choose option 4. Once this is a done, a new build number is created which will be displayed in the menu header. Option 5 is for running the created container image locally on the client without using the sandbox. In this scenario, the encrypted algorithms is decrypted and run, but the container image itself is unencrypted. 

To encrypt and sign the container image, choose option 6. The encryption is done using a randomly generated key pair - the private key needed for decryption is saved in the build directory. The signing key and the "domain" specified in the config file are using for signing the image. When option 6 is done, the build directory will contain the image measurement, a tar file with the image, and the image private key.

Option 7 submits the tar file generated with option 6 to a designated central registry. In standalone mode, this operation involves importing the tar file to create the container image and then pushing this encrypted container image to the designated central registry. In API mode, submitting a tar file would involve the API server as described above.

The tarfile for an image can potentially be very large. A big contributor to this size could be the base image used to build the container image for the algorithm (created in option 4). Transferring a very large tarfile to a GCS bucket from the client, the API server backend having to fetch this large tarfile from the same bucket, and then pushing this large image to the central registry can all be highly time consuming. An optimization is introduced to address this issue, and it involves the use of a reference image which is the same as the base image used to build the algorithm container image. This optimization is enabled with the following in the config file.
```sh
export SCLI_USE_REF=true
export SCLI_REF_ALGO_IMAGE=sensoriant.azurecr.io/priv-comp/sensrefimage:11302020
export SCLI_REF_ALGO_CREDS=<username>:<password>
```
SCLI_USE_REF should be set to *false* to disable this optimization. SCLI_REF_ALGO_CREDS refers to the registry credentials to fetch the SCLI_REF_ALGO_IMAGE (these would be credentials for sensoriant.azurecr.io in the above configuration).

In standalone mode, Option 8 simply checks that the machine key needed to encrypt the image private key is available. In API mode, the API server is contacted for  obtaining the machine key for the created platform. Once the platform key is obtained, Option 9 is used to encrypt the input dataset decryption key with the platform key and to upload this encrypted key to the API server.

Option 10 creates the pipeline object and transfers it to a sandbox. Creating the pipeline object involves pulling together information generated in the previous option selections (options 1/2, 4, 6, 7, 8, 9) and involves encryption of various keys such as the algorithm encryption key and the image decryption key using the platform key for the platform where this pipeline is intended to run on. In standalone mode, once this pipeline object is created, it is simply copied over to the sandbox directory in the ADK. In API mode, the pipeline object is submitted to the API server which then sends it to the appropriate sandbox.

In standalone mode, this pipeline can be run by invoking the sandbox menu in the sandbox directory. In API mode, Option 11 is used to invoke a run of the selected pipeline on the selected platform.

Option 12 is only used in the API mode. When this option is selected, the output of the pipeline run that was invoked through option 11 is fetched from a GCS bucket, the keys to decrypt it are obtained from the API server, and the decrypted output is placed in client/image/volume/decrypt-output.

Option 13 deletes the current build and unsets the CURRENT_BUILD_SCLI. A new build can be created using option 4 or an existing build can be selected using option 3 if desired.

## Sandbox
### Initialization
Sandbox initialization is relatively simple. The single most important thing to do is to set standalone mode as true or false (the default is false). This mode is set in a file called standalone.config in the sandbox directory.
```sh
> cd $HOME/adk/sandbox
> cat standalone.config
export SBOX_STANDALONE=false
...
```
If you set SBOX_STANDALONE to *true*, the central container registry information needs to be set appropriately in the same file as below.
```sh
export SBOX_STANDALONE=true
if [ "$SBOX_STANDALONE" == "true" ]; then 
...
  export SBOX_SENSE_REG=nferalgos.azurecr.io 
  export SBOX_SENSE_REG_USER=<username>:<password> 
...
else
...
```
No additional initialization is needed.
### Invoking the Sandbox Menu
To invoke the sandbox menu, change directory into sample/sandbox and run the sbox-menu.sh script. Pay attention to two files before you invoke this sbox menu - *config* and *pipeline.json*. The file *config* is generated using *pipeline.json* - so, if you run sbox-menu.sh with a *config* file present, then *pipeline.json* is ignored and the run uses information from the *config* file. 
```sh
> ./sbox-menu.sh
Using existing config file ...
Please remove ./config if you want to reparse pipeline ...

...
```
To run the pipeline object, ensure that the config file is removed before starting the menu. If there is no *config* and no *pipeline.json*, the menu will not start.
```sh
> ./sbox-menu.sh
No pipeline to exec
```
When started after properly submitting a pipeline, the following menu is displayed. Note that build number is always shown as *default*. This is because, unlike the client, the sandbox only operates on a single pipeline at a time. The pipeline object is used to generate the config file and populate sandbox/image/sdata/default with any information related to this pipeline that is needed for running the pipeline. This same directory is used for any further pipeline related content created as the menu is navigated. 
```sh
> ./sbox-menu.sh 
Starting ...
Checking product version
Starting sandbox menu for build number: default
-------------------------------------------
Sensoriant Sandbox Release: VERSION_1_1_0
-------------------------------------------
1) Setup Sandbox                        5) Run Image
2) Verify Image Measurement             6) Run all
3) Decrypt Algo Image and DataSet Keys  7) Quit
4) Verify Signature and Decrypt Image
Please enter your choice: 
```
Option 1, Setup Sandbox must be selected before anything else the first time the menu is invoked. While it is not required to do this again, it doesn't hurt to do this each time sbox-menu.sh is started. 

Option 2 fetches the encrypted image related data and verifies the container measurement by comparing with the measurement submitted as part of the pipeline. Note that, at this time, the image is still encrypted and the keys needed for decryption are still encrypted.

Once the measurement is verified successfully, Option 3 is used to decrypt the various keys needed to decrypt the container image, algorithm, and the datasets. In standalone mode, the prepopulated machine key is used for this decryption. In API mode, other platform centric procedures are used. For example, on a secure platform equipped with a TPM in the Google cloud, the TPM is used. 

Option 4 is used to first verify the image signature, and if successful, to decrypt the image and push the decrypted image to the local registry at localhost:6000.

Option 5 can then be used to pull the decrypted image from localhost:6000 and run it. In standalone mode, data in sandbox/image/volumes/algorithm-input is used as input data and corresponding output is placed in sandbox/image/volumes/algorithm-output. When not in standalone mode, the data doesn't not reside in the sandbox ADK and none of the decrypted keys is stored on disk.

Option 6 can be used to run Option 1 through 5.
