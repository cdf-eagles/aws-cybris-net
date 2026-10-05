#!/bin/sh
# Deletes the default VPC in every enabled region, refusing any that still
# holds a network interface, and skipping any region it cannot reach. Dry
# run unless --apply is given. Needs the administrator profile; AWS_PROFILE
# must be set.
#
#   sh scripts/delete-default-vpcs.sh            # list what would go
#   sh scripts/delete-default-vpcs.sh --apply    # delete
set -eu

apply=false
[ "${1:-}" = "--apply" ] && apply=true
found=0

for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  if ! vpc=$(aws ec2 describe-vpcs --region "$region" --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text 2>/dev/null); then
    echo "$region: not reachable, skipped"
    continue
  fi
  [ "$vpc" = "None" ] && continue
  found=$((found + 1))

  enis=$(aws ec2 describe-network-interfaces --region "$region" --filters "Name=vpc-id,Values=$vpc" --query 'length(NetworkInterfaces)' --output text)
  if [ "$enis" != "0" ]; then
    echo "$region $vpc: $enis network interface(s) attached, left alone"
    continue
  fi

  if [ "$apply" = false ]; then
    echo "$region $vpc: would delete"
    continue
  fi

  for igw in $(aws ec2 describe-internet-gateways --region "$region" --filters "Name=attachment.vpc-id,Values=$vpc" --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --region "$region" --internet-gateway-id "$igw" --vpc-id "$vpc"
    aws ec2 delete-internet-gateway --region "$region" --internet-gateway-id "$igw"
  done
  for subnet in $(aws ec2 describe-subnets --region "$region" --filters "Name=vpc-id,Values=$vpc" --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --region "$region" --subnet-id "$subnet"
  done
  aws ec2 delete-vpc --region "$region" --vpc-id "$vpc"
  echo "$region $vpc: deleted"
done

[ "$found" = 0 ] && echo "no default VPC in any reachable region"
exit 0
