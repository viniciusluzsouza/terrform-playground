#!/bin/bash

# Destroy infra
terraform destroy -auto-approve

# Clean up local
rm -rf lambda/lambda.zip lambda/package