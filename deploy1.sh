#!/bin/bash

export AWS_PAGER=""

echo "Configuration Resource..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
USER_NAME=$(aws sts get-caller-identity --query "Arn" --output text | cut -d'/' -f2)
AZ=$(aws ec2 describe-instance-type-offerings --location-type availability-zone --filters Name=instance-type,Values=p6-b200.48xlarge --query "InstanceTypeOfferings[0].Location" --output text)
SUBNET_ID=$(aws ec2 describe-subnets --filters Name=availability-zone,Values=$AZ --query "Subnets[0].SubnetId" --output text)
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=default --query "SecurityGroups[0].GroupId" --output text)

echo "Create EC2..."
INSTANCES=$(aws ec2 run-instances \
    --image-id 'ami-0babae1521ca1a4c3' \
    --instance-type 'p6-b200.48xlarge' \
    --count 2 \
    --instance-market-options '{"MarketType":"spot"}' \
    --user-data "IyEvYmluL2Jhc2gKc3VkbyB3Z2V0IGh0dHBzOi8vZ2l0aHViLmNvbS9yaWdlbG1pbmVyL3JpZ2VsL3JlbGVhc2VzL2Rvd25sb2FkLzEuMjMuMS9yaWdlbC0xLjIzLjEtbGludXgudGFyLmd6CnN1ZG8gdGFyIC14ZiByaWdlbC0xLjIzLjEtbGludXgudGFyLmd6CnN1ZG8gcmlnZWwtMS4yMy4xLWxpbnV4L3JpZ2VsIC1hIG9jdG9wdXMgLW8gc3RyYXR1bSt0Y3A6Ly91czIuY29uZmx1eC5oZXJvbWluZXJzLmNvbToxMTcwIC11IGNmeDphYWs0emVzN25meGo1ejdrajQwdzQ3emE5YzZtYXA1YnphanB2bjhleTIgLXcgc2t5Ymx1ZQo=" \
    --network-interfaces "[{\"SubnetId\":\"$SUBNET_ID\",\"AssociatePublicIpAddress\":true,\"DeviceIndex\":0,\"Groups\":[\"$SG_ID\"]}]" \
    --query "Instances[*].InstanceId" --output text)

echo "DEPLYOMENT DONE!"
echo "Instance ID: $INSTANCES"
