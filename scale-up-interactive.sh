#!/bin/bash
set -e

read -p "Enter access key: " access_key
read -p "Enter secret key: " secret_key
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

if [ $username = "user1" ]
then
    clusters_to_be_scaled_up_list=( 'cluster1' )
elif [ $username = "user2" ]
then
    clusters_to_be_scaled_up_list=( 'cluster2' )
fi

aws ecs list-clusters | jq -r '.clusterArns[]' | awk -F '/' '{print $2}' > ecs_cluster_list.txt

for each_ecs_cluster in $(cat ecs_cluster_list.txt)
do
    for cluster_to_be_scaled_up in "${clusters_to_be_scaled_up_list[@]}"
    do
        if [ $each_ecs_cluster = $cluster_to_be_scaled_up ]
        then

            aws ecs describe-clusters --cluster $cluster_to_be_scaled_up | jq -r '.clusters[].capacityProviders[]' | xargs -L 1 aws ecs describe-capacity-providers --capacity-providers | jq -r '.capacityProviders[].autoScalingGroupProvider.autoScalingGroupArn' | awk -F '/' '{print $2}' > asg_names.txt
            
            for asg in $(cat asg_names.txt)
            do
                echo "scaling up ASG: $asg"
                aws autoscaling update-auto-scaling-group --auto-scaling-group-name $asg --min-size 1 --desired-capacity 1 --max-size 2 
                sleep 1
            done

            aws ecs list-services --cluster $cluster_to_be_scaled_up | jq -r '.serviceArns[]' | awk -F '/' '{print $3}' > service_list.txt

            for service in $(cat service_list.txt)
            do
                echo "making desired count as 1 for service: $service in $cluster_to_be_scaled_up cluster."
                aws ecs update-service --cluster $cluster_to_be_scaled_up --service $service --desired-count 1 
            done
            #sleep 300
            #aws ecs list-services --cluster $cluster_to_be_scaled_up | jq -r '.serviceArns[]' | awk -F '/' '{print $3}' | xargs -L 1 aws ecs list-tasks --cluster $cluster_to_be_scaled_up --service | jq -r '.taskArns[]' | awk -F '/' '{print $3}' | xargs -L 1 aws ecs stop-task --task
            
            rm -rf service_list.txt
        fi
    done

done


rm -rf ecs_cluster_list.txt
rm -rf asg_names.txt
rm -rf cred.json
