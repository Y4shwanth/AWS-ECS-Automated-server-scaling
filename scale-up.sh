#!/bin/bash 

set -e 

aws ecs list-clusters | jq -r '.clusterArns[]' | awk -F '/' '{print $2}' > ecs_cluster_list.txt

clusters_to_be_scaled_up_list=('ecs-appmesh-test')

while read -r each_ecs_cluster 
do
    for cluster_to_be_scaled_up in "${clusters_to_be_scaled_up_list[@]}"
    do
        if [ "$each_ecs_cluster" = "$cluster_to_be_scaled_up" ]
        then

            aws ecs describe-clusters --cluster "$cluster_to_be_scaled_up" | jq -r '.clusters[].capacityProviders[]' | xargs -L 1 aws ecs describe-capacity-providers --capacity-providers | jq -r '.capacityProviders[].autoScalingGroupProvider.autoScalingGroupArn' | awk -F '/' '{print $2}' > asg_names.txt
            
            while read -r asg 
            do
                echo "scaling up ASG: $asg"
                aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$asg" --min-size 1 --desired-capacity 1 --max-size 2 
                sleep 1
            done < asg_names.txt

            aws ecs list-services --cluster "$cluster_to_be_scaled_up" | jq -r '.serviceArns[]' | awk -F '/' '{print $3}' > service_list.txt

            while read -r service 
            do
                echo "making desired count as 1 for service: $service in $cluster_to_be_scaled_up cluster."
                aws ecs update-service --cluster "$cluster_to_be_scaled_up" --service "$service" --desired-count 1 
            done < service_list.txt
            # sleep 200
            # aws ecs list-services --cluster "$cluster_to_be_scaled_up" | jq -r '.serviceArns[]' | awk -F '/' '{print $3}' | xargs -L 1 aws ecs list-tasks --cluster "$cluster_to_be_scaled_up" --service | jq -r '.taskArns[]' | awk -F '/' '{print $3}' | xargs -L 1 aws ecs stop-task --cluster "$cluster_to_be_scaled_up" --task
            rm -rf service_list.txt
        fi
    done

done < ecs_cluster_list.txt

rm -rf ecs_cluster_list.txt
rm -rf asg_names.txt
