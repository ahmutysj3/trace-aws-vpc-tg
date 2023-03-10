##################################################################################
//////////////////////////////// VPCs ////////////////////////////////////////////
##################################################################################

resource "aws_vpc" "main" {
  for_each   = { for k, v in var.vpc_params : k => v }
  cidr_block = each.value.cidr
  tags = {
    Name = "${var.net_name}_${each.key}_vpc"
    type = each.value.type
  }
}

resource "aws_internet_gateway" "hub" {
  vpc_id = join("", [for v in aws_vpc.main : v.id if v.tags.type == "hub"])
  tags = {
    Name = "${var.net_name}_internet_gateway"
  }
}

##################################################################################
//////////////////////////////// Subnets /////////////////////////////////////////
##################################################################################

locals {
  hub_subnet_names = {
    "inside"  = 0
    "outside" = 1
    "mgmt"    = 2
    "ha"      = 3
    "tg"      = 4
  }
}

resource "aws_subnet" "hub" {
  for_each = local.hub_subnet_names
  vpc_id                  = join("", [for v in aws_vpc.main : v.id if v.tags.type == "hub"])
  cidr_block              = cidrsubnet(aws_vpc.main[join("", [for k, v in var.vpc_params : k if v.type == "hub"])].cidr_block, 6, each.value)
  map_public_ip_on_launch = each.value > 0 ? true : false

  tags = {
    Name = "${var.net_name}_${each.key}_subnet"
    type = "hub"
    vpc  = join("", [for k, v in var.vpc_params : k if v.type == "hub"])
  }
}

resource "aws_subnet" "spokes" {
  for_each   = var.subnet_params
  vpc_id     = aws_vpc.main[each.value.vpc].id
  cidr_block = cidrsubnet(aws_vpc.main[each.value.vpc].cidr_block, each.value.cidr_mask - tonumber(element(split("/", aws_vpc.main[each.value.vpc].cidr_block), 1)), lookup({ for k, v in keys({ for k, v in var.subnet_params : k => v if v.vpc == each.value.vpc }) : v => k }, each.key))
  map_public_ip_on_launch = each.value.public

  tags = {
    Name = "${var.net_name}_${each.key}_subnet"
    vpc  = each.value.vpc
    type = "spoke"
  }
}

resource "aws_subnet" "transit_gateway" {
  for_each   = { for k, v in var.vpc_params : k => v if v.type == "spoke" }
  vpc_id     = aws_vpc.main[each.key].id
  cidr_block = cidrsubnet(aws_vpc.main[each.key].cidr_block, tonumber(element(split("/", element(values({ for k, v in aws_subnet.spokes : k => v.cidr_block if v.tags.vpc == each.key }), 0)), 1)) - tonumber(element(split("/", aws_vpc.main[each.key].cidr_block), 1)), length({ for k, v in aws_subnet.spokes : k => v if v.tags.vpc == each.key }))

  tags = {
    Name = "${var.net_name}_${each.key}_tg_subnet"
    vpc  = each.key
    type = "spoke"
  }
}

##################################################################################
//////////////////////// Transit Gateway & attachments ///////////////////////////
##################################################################################

// ****** Transit Gateway ***** //
resource "aws_ec2_transit_gateway" "trace" {
  transit_gateway_cidr_blocks     = [for sub in aws_subnet.hub : sub.cidr_block if sub.tags.Name == "${var.net_name}_tg_subnet"]
  amazon_side_asn                 = var.tg_params.amazon_side_asn == null ? 64512 : var.tg_params.amazon_side_asn
  dns_support                     = var.tg_params.enable_dns_support == true ? "enable" : "disable"
  multicast_support               = var.tg_params.enable_multicast_support == true ? "enable" : "disable"
  vpn_ecmp_support                = var.tg_params.enable_vpn_ecmp_support == true ? "enable" : "disable"
  auto_accept_shared_attachments  = var.tg_params.auto_accept_shared_attachments == true ? "enable" : "disable"
  default_route_table_association = var.tg_params.default_route_table_association == true ? "enable" : "disable"
  default_route_table_propagation = var.tg_params.default_route_table_propagation == true ? "enable" : "disable"
  tags = {
    Name = var.tg_params.tg_name
  }
}

// ******  Route Tables ***** //
resource "aws_ec2_transit_gateway_route_table" "spokes" {
  for_each           = aws_ec2_transit_gateway_vpc_attachment.spokes
  transit_gateway_id = aws_ec2_transit_gateway.trace.id

  tags = {
    Name = "${var.net_name}_${each.key}_tg_rt"
  }
}

resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.trace.id

  tags = {
    Name = "${var.net_name}_hub_tg_rt"
  }
}

// ******  Routes ***** //
resource "aws_ec2_transit_gateway_route" "spoke_to_hub" {
  for_each                       = { for k, v in var.vpc_params : k => v if v.type == "spoke" }
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes[each.key].id
}

resource "aws_ec2_transit_gateway_route" "hub_to_spokes" {
  for_each                       = { for k, v in var.vpc_params : k => v if v.type == "spoke" }
  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spokes[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

// ******  Route table associations ***** //
resource "aws_ec2_transit_gateway_route_table_association" "spokes" {
  for_each                       = { for k, v in var.vpc_params : k => v if v.type == "spoke" }
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spokes[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spokes[each.key].id
}

resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

// ******  VPC Attachments ***** //
resource "aws_ec2_transit_gateway_vpc_attachment" "spokes" {
  for_each                                        = { for k, v in var.vpc_params : k => v if v.type == "spoke" }
  subnet_ids                                      = [aws_subnet.transit_gateway[each.key].id]
  transit_gateway_id                              = aws_ec2_transit_gateway.trace.id
  vpc_id                                          = aws_subnet.transit_gateway[each.key].vpc_id
  transit_gateway_default_route_table_association = false

  tags = {
    Name = "${var.net_name}_tg_to_${each.key}_vpc_attach"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  subnet_ids                                      = [lookup({for k,v in aws_subnet.hub : k => v.id if length(regexall("${var.net_name}_tg_subnet",v.tags.Name)) > 0},"tg")]
  transit_gateway_id                              = aws_ec2_transit_gateway.trace.id
  vpc_id                                          = join("", [for v in aws_vpc.main : v.id if v.tags.type == "hub"])
  transit_gateway_default_route_table_association = false

  tags = {
    Name = "${var.net_name}_tg_to_hub_vpc_attach"
  }
}

// ******  Network Manager & TG Registration ***** //
resource "aws_networkmanager_global_network" "trace" {
  description = "trace's aws wan/global network container"
  tags = {
    Name = "${var.net_name}_global_network"
  }
}

resource "aws_networkmanager_transit_gateway_registration" "trace" {
  global_network_id   = aws_networkmanager_global_network.trace.id
  transit_gateway_arn = aws_ec2_transit_gateway.trace.arn
}

##################################################################################
//////////////////////// Subnet Route Tables /////////////////////////////////////
##################################################################################

resource "aws_route_table" "spokes" {
  for_each = { for k, v in var.vpc_params : k => v if v.type == "spoke" }
  vpc_id   = aws_vpc.main[each.key].id

  route {
    cidr_block         = "0.0.0.0/0"
    transit_gateway_id = aws_ec2_transit_gateway.trace.id
  }

  tags = {
    Name = "${var.net_name}_${each.key}_subnet_rt"
  }
}

resource "aws_route_table_association" "spokes" {
  for_each       = var.subnet_params
  subnet_id      = aws_subnet.spokes[each.key].id
  route_table_id = aws_route_table.spokes[each.value.vpc].id
}