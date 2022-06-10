# Algorithm Image

This directory contains all files necessary to build the algorithm image.
It contains an encrypted python program that operates on encrypted data from
the input stage and pushes its results into a volume which is subsequently read
by the output program.

## Image Building

As this image contains encrypted code, the build process requires a
preprocessing step in which the files are encrypted and authenticated.
This is done with the `encrypt_algorithm.sh` script.
After this step the policies of the algorithm owner must be updated.

