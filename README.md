# AWS Transit Gateway VPC Network

AWS Network Environment using Transit Gateway

## Overview

This terraform plan builds a network in **AWS**.

Use of this module/s will require setting up **Terraform AWS Provider & AWS-CLI** (along w/credentials setup etc) before running terraform init

## Instructions

- define region, network name, supernet, and vpc names for network in the *terraform.tfvars* file supernet variable

## Network Structure

### Hub-Spoke Design utilizing Transit Gateway

- `Hub` Virtual Private Cloud
    > security vpc where network virtual appliance will sit
- `DMZ` Virtual Private Cloud
- `App` Virtual Private Cloud
- `DB` Virtual Private Cloud

## Resources Used

- aws_vpc
- aws_subnet
- aws_route_table
- aws_route_table_association
- aws_route
- aws_security_group
- aws_vpc_security_group_ingress_rule
- aws_vpc_security_group_egress_rule
- aws_internet_gateway
- aws_ec2_transit_gateway
- aws_ec2_transit_gateway_route_table
- aws_ec2_transit_gateway_route
- aws_ec2_transit_gateway_route_table_association
- aws_ec2_transit_gateway_vpc_attachment
- aws_networkmanager_global_network
- aws_networkmanager_transit_gateway_registration

## Notes

- Adding more than 1 x "hub" type VPC will *break* the module!
- the keys for the spoke VPCs in var.vpc_params CANNOT be changed. 
    - The names are used for security groups later in the module