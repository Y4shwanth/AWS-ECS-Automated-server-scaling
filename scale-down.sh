#!/bin/bash 

set -e 

aws ecs list-clusters | jq -r '.clusterArns[]' | awk -F '/' '{print $2}' > ecs_cluster_list.txt

clusters_to_be_scaled_down_list=( 'cluster-name' )

while read -r each_ecs_cluster 
do
    for cluster_to_be_scaled_down in "${clusters_to_be_scaled_down_list[@]}"
    do 
        if [ "$each_ecs_cluster" = "$cluster_to_be_scaled_down" ]
        then
            aws ecs list-container-instances --cluster "$cluster_to_be_scaled_down" --query 'containerInstanceArns[]' --output text | xargs -L 1 aws ecs describe-container-instances --cluster "$cluster_to_be_scaled_down" --container-instances | jq '.containerInstances[].ec2InstanceId' -r > instance_id.txt
            aws ecs list-services --cluster "$cluster_to_be_scaled_down" | jq -r '.serviceArns[]' | awk -F '/' '{print $3}' > service_list.txt
            while read -r service 
            do
                echo "making desired count as zero for service: $service in $cluster_to_be_scaled_down cluster."
                aws ecs update-service --cluster "$cluster_to_be_scaled_down" --service "$service" --desired-count 0 
            done < service_list.txt

            rm -rf service_list.txt

            while read -r instance_id 
            do
                asg_name=$(aws autoscaling describe-auto-scaling-instances --instance-ids "$instance_id" --query "AutoScalingInstances[].AutoScalingGroupName" --output text)
                echo "removing scale in protection for instance: $instance_id in ASG:$asg_name."
                aws autoscaling set-instance-protection --instance-ids "$instance_id" --auto-scaling-group-name "$asg_name" --no-protected-from-scale-in
                sleep 1
                echo "scaling down ASG: $asg_name"
                aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$asg_name" --min-size 0 --max-size 0 --desired-capacity 0
                sleep 1
            done < instance_id.txt

            rm -rf instance_id.txt

        fi
    done
done < ecs_cluster_list.txt

rm -rf ecs_cluster_list.txt
