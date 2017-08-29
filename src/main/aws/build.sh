#!/usr/bin/env bash



# This script is to implement the synchronization between two s3 buckets

###
# To implement the sync between two s3 buckets, there are many configuration
# and provision steps need to be done, which include at least:
# * Create S3BucketPolicy for source bucket;
# * Create S3BucketPolicy for target bucket;
# * Put notification configuration for source bucket;
# * Create lambda function to copy objects from source to target bucket;
# * and so on.
##

##
# Website and Github:
# https://github.com/neorayer/s3sync
#

# Exit immediately if a command exits with a non-zero status.
set -o errexit

# parameters
declare -r STACK_NAME="s3sync"

# global constants
declare -r TMP_FILE_PREFIX=${TMPDIR:-/tmp}/prog.$$
declare -r SCRIPTPATH=$( cd $(dirname ${BASH_SOURCE[0]}) > /dev/null; pwd -P )

function cloudformation_stack_exists() {
    sqs_queue_arn=$(aws cloudformation list-exports \
            --output text \
            --query "Exports[?Name=='${STACK_NAME}-SqsQueueArn'].Value")
    if [[ -z "${sqs_queue_arn}" ]]; then
        return 1  # not exist
    else
        return 0  # exists
    fi
}

# Delete Exists Cloudformation Stack
function delete_cloudformation_stack() {
    log "delete cloudformation stack ${STACK_NAME}"
    exe aws cloudformation delete-stack \
            --stack-name "${STACK_NAME}"
    log "stack deleting submitted, waiting for finishing"
    exe aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}"
    log "stack deleted"
}

# Create cloudformation Stack
function create_cloudformation_stack() {
    log "creating cloudformation stack ${STACK_NAME}"
    exe aws cloudformation create-stack \
            --stack-name "${STACK_NAME}"\
            --template-body file://cf-s3sync.yml \
            --capabilities CAPABILITY_NAMED_IAM
    log "stack creating submitted, waiting for finishing"
    exe aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}"
    log "stack created"
}

# Update Cloudformation Stack
function update_cloudformation_stack() {
    log "updating cloudformation stack ${STACK_NAME}"
    exe aws cloudformation update-stack \
            --stack-name "${STACK_NAME}"\
            --template-body file://cf-s3sync.yml \
            --capabilities CAPABILITY_NAMED_IAM
    log "stack updating submitted, waiting for finishing"
    exe aws cloudformation wait stack-update-complete --stack-name "${STACK_NAME}"
    log "stack updated"
}

function put_s3_notification_configuration() {
    # Get Export Values of Cloudformation Stack
    sqs_queue_arn=$(aws cloudformation list-exports \
            --output text \
            --query "Exports[?Name=='${STACK_NAME}-SqsQueueArn'].Value")
    source_s3bucket_name=$(aws cloudformation list-exports \
            --output text \
            --query "Exports[?Name=='${STACK_NAME}-SourceS3BucketName'].Value")

    # Create s3 bucket notification configuration file
    noti_config=$(sed -e "s/\${sqs_queue_arn}/${sqs_queue_arn}/" s3-bucket-notification.json)
    temppath="${TMP_FILE_PREFIX}.${STACK_NAME}.notification-configuration.json"
    log "create a temporary s3 notification-configuration file: ${temppath}"
    echo "${noti_config}" > "${temppath}"

    # Put S3 Bucket Notification Configuration
    exe aws s3api put-bucket-notification-configuration \
            --bucket ${source_s3bucket_name} \
            --notification-configuration "file://${temppath}"
}

function exe() {
    log "$@"
    $@
}


function log() {
    echo ">>>>>> $@"
}

function cleanup() {
    exe rm -f ${TMP_FILE_PREFIX}.*

    echo "always implement this" && exit 100
}

function main() {
    if $(cloudformation_stack_exists) ;then
        update_cloudformation_stack
    else
        #delete_cloudformation_stack
        create_cloudformation_stack
    fi

    put_s3_notification_configuration
}

# set a trap for (calling) cleanup all stuff before process
# termination by SIGHUBs
trap "cleanup; exit 1" 1 2 3 13 15

main "$@"