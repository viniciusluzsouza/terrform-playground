#!/bin/bash

# Build
mkdir lambda/package
pip3 install -r requirements.txt --target lambda/package
cp lambda/lambda.py lambda/package/

# Create the resources
terraform init
terraform apply -auto-approve