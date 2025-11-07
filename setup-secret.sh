#!/bin/bash

set -e

[ ! -z ${CI} ] || . ./config

echo $ENVIRONMENT_NAME

STACK_NAME="$ENVIRONMENT_NAME-$COMPONENT_NAME-$PART_NAME-secrets"
TEMPLATE_FILE="./create-secret.yaml"

echo "Deploying Secret stack: $STACK_NAME"

aws cloudformation deploy \
    --template-file "$TEMPLATE_FILE" \
    --stack-name "$STACK_NAME" \
    --parameter-overrides \
        StellarAddress="$STELLAR_ADDRESS" \
        Environment="$ENVIRONMENT_NAME" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --region $AWS_REGION