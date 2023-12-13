#!/bin/bash
set -e
read -p "Enter Sandbox access key: " access_key
read -p "Enter Sandbox secret key: " secret_key
read -p "Enter AWS region: " aws_region

aws configure set aws_access_key_id $access_key
aws configure set aws_secret_access_key $secret_key
aws configure set default.region $aws_region
aws configure set default.output json

read -p "Enter username as in sandbox: " username
read -p "Enter the MFA token code for sandbox:" token_code

aws  sts  get-session-token  --duration-seconds 129600 --serial-number arn:aws:iam::333262764494:mfa/$username --token-code $token_code > cred.json

AWS_ACCESS_KEY_ID=$(cat cred.json | jq -r '.Credentials.AccessKeyId')
AWS_SECRET_ACCESS_KEY=$(cat cred.json | jq -r '.Credentials.SecretAccessKey')
AWS_SESSION_TOKEN=$(cat cred.json | jq -r '.Credentials.SessionToken')

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN

aws ecs list-clusters | jq -r '.clusterArns[]' | awk -F '/' '{print $2}' > ecs_cluster_list.txt

if [ $username = "user1" ]
then
    clusters_to_be_scaled_down_list=( 'cluster1' )
elif [ $username = "user2" ]
then
    clusters_to_be_scaled_down_list=( 'cluster2' )
fi

for each_ecs_cluster in $(cat ecs_cluster_list.txt)
do
    for cluster_to_be_scaled_down in "${clusters_to_be_scaled_down_list[@]}"
    do 
        if [ $each_ecs_cluster = $cluster_to_be_scaled_down ]
        then
            aws ecs list-container-instances --cluster $cluster_to_be_scaled_down --query 'containerInstanceArns[]' --output text | xargs -L 1 aws ecs describe-container-instances --cluster $cluster_to_be_scaled_down --container-instances | jq '.containerInstances[].ec2InstanceId' -r > instance_id.txt
            aws ecs list-services --cluster $cluster_to_be_scaled_down | jq -r '.serviceArns[]' | awk -F '/' '{print $3}' > service_list.txt
            for service in $(cat service_list.txt)
            do
                echo "making desired count as zero for service: $service in $cluster_to_be_scaled_down cluster."
                aws ecs update-service --cluster $cluster_to_be_scaled_down --service $service --desired-count 0 
            done

            rm -rf service_list.txt

            for instance_id in $(cat instance_id.txt)
            do
                asg_name=$(aws autoscaling describe-auto-scaling-instances --instance-ids $instance_id --query "AutoScalingInstances[].AutoScalingGroupName" --output text)
                echo "removing scale in protection for instance: $instance_id in ASG:$asg_name."
                aws autoscaling set-instance-protection --instance-ids $instance_id --auto-scaling-group-name $asg_name --no-protected-from-scale-in
                sleep 1
                echo "scaling down ASG: $asg_name"
                aws autoscaling update-auto-scaling-group --auto-scaling-group-name $asg_name --min-size 0 --max-size 0 --desired-capacity 0
                sleep 1
            done

            rm -rf instance_id.txt

        fi
    done
done

rm -rf ecs_cluster_list.txt
rm -rf cred.json
