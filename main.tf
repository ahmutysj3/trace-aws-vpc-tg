resource "aws_networkmanager_global_network" "trace" {
  description = "trace's aws wan/global network container"
  tags = {
    Name = "${var.net_name}_global_network"
  }
}

resource "aws_vpc" "hub" {
  for_each = {
    for k, v in var.vpc_params : k => v if v.type == "hub"
  }
  cidr_block = each.value.cidr
  tags = {
    Name = "${var.net_name}_${each.key}_vpc"
  }
}

resource "aws_vpc" "spokes" {
  for_each = {
    for k, v in var.vpc_params : k => v if v.type == "spoke"
  }
  cidr_block = each.value.cidr
  tags = {
    Name = "${var.net_name}_${each.key}_vpc"
  }
}

resource "aws_subnet" "spokes" {
  for_each                = var.subnet_params
  vpc_id                  = aws_vpc.spokes[each.value.vpc].id
  cidr_block              = cidrsubnet(aws_vpc.spokes[each.value.vpc].cidr_block, each.value.cidr_mask - lookup(local.combined_vpc_mask, each.value.vpc), lookup(local.combined_net_num, each.key))
  map_public_ip_on_launch = each.value.public
}

resource "aws_ec2_transit_gateway" "trace" {
  description                     = "trace test transit gateway"
  transit_gateway_cidr_blocks     = [var.supernet]
  amazon_side_asn                 = 64512
  dns_support                     = "enable"
  multicast_support               = "enable"
  vpn_ecmp_support                = "enable"
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  tags = {
    Name = "${var.net_name}_test_tg"
  }
}

/* resource "aws_ec2_transit_gateway_vpc_attachment" "trace" {
  subnet_ids         = [aws_subnet.example.id]
  transit_gateway_id = aws_ec2_transit_gateway.example.id
  vpc_id             = aws_vpc.example.id
} */

# creates a map of subnet params with filter on vpc name
locals {
  app_subnets = {
    for k, v in var.subnet_params : k => v if v.vpc == "app"
  }
  dmz_subnets = {
    for k, v in var.subnet_params : k => v if v.vpc == "dmz"
  }
  db_subnets = {
    for k, v in var.subnet_params : k => v if v.vpc == "db"
  }
}

# returns a string with the cidr net mask of each vpc
locals {
  app_vpc_mask = {
    "app" = tonumber(element(split("/", aws_vpc.spokes["app"].cidr_block), 1))
  }
  dmz_vpc_mask = {
    "dmz" = tonumber(element(split("/", aws_vpc.spokes["dmz"].cidr_block), 1))
  }
  db_vpc_mask = {
    "db" = tonumber(element(split("/", aws_vpc.spokes["db"].cidr_block), 1))
  }
  combined_vpc_mask = merge(
    {
      "app" = tonumber(element(split("/", aws_vpc.spokes["app"].cidr_block), 1))
    },
    {
      "dmz" = tonumber(element(split("/", aws_vpc.spokes["dmz"].cidr_block), 1))
    },
    {
      "db" = tonumber(element(split("/", aws_vpc.spokes["db"].cidr_block), 1))
    }
  )
}

# creates a map of subnets to their network number (indexes by vpc)
locals {
  combined_net_num = merge(
    {
      for k, v in keys(local.app_subnets) : v => k
    },
    {
      for k, v in keys(local.dmz_subnets) : v => k
    },
    {
      for k, v in keys(local.db_subnets) : v => k
    }
  )
}