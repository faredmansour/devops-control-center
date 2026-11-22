data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Keep subnet-to-AZ mapping deterministic: list index 0 belongs to AZ 0, etc.
  selected_availability_zones = length(var.availability_zones) == 2 ? var.availability_zones : try(slice(data.aws_availability_zones.available.names, 0, 2), [])

  public_subnets = {
    for index, az in local.selected_availability_zones : tostring(index) => {
      az   = az
      cidr = var.public_subnet_cidrs[index]
    }
  }

  private_application_subnets = {
    for index, az in local.selected_availability_zones : tostring(index) => {
      az   = az
      cidr = var.private_application_subnet_cidrs[index]
    }
  }

  private_data_subnets = {
    for index, az in local.selected_availability_zones : tostring(index) => {
      az   = az
      cidr = var.private_data_subnet_cidrs[index]
    }
  }

  subnet_cidrs = concat(
    var.public_subnet_cidrs,
    var.private_application_subnet_cidrs,
    var.private_data_subnet_cidrs,
  )

  # Convert IPv4 addresses to integers so we can validate containment and overlap.
  ipv4_ranges = {
    for index, cidr in concat([var.vpc_cidr], local.subnet_cidrs) : tostring(index) => {
      start = sum([
        for octet_index, octet in split(".", cidrhost(cidr, 0)) :
        tonumber(octet) * pow(256, 3 - octet_index)
      ])
      end = sum([
        for octet_index, octet in split(".", cidrhost(cidr, -1)) :
        tonumber(octet) * pow(256, 3 - octet_index)
      ])
    }
  }

  subnet_cidrs_within_vpc = alltrue([
    for index in range(length(local.subnet_cidrs)) :
    local.ipv4_ranges[tostring(index + 1)].start >= local.ipv4_ranges["0"].start &&
    local.ipv4_ranges[tostring(index + 1)].end <= local.ipv4_ranges["0"].end
  ])

  subnet_cidrs_are_non_overlapping = alltrue(flatten([
    for index in range(length(local.subnet_cidrs)) : [
      for other_index in range(length(local.subnet_cidrs)) :
      index >= other_index ? true : (
        local.ipv4_ranges[tostring(index + 1)].start > local.ipv4_ranges[tostring(other_index + 1)].end ||
        local.ipv4_ranges[tostring(other_index + 1)].start > local.ipv4_ranges[tostring(index + 1)].end
      )
    ]
  ]))
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  lifecycle {
    precondition {
      condition     = length(local.selected_availability_zones) == 2
      error_message = "The network module requires exactly two available Availability Zones in the selected AWS region."
    }

    precondition {
      condition = alltrue([
        for az in local.selected_availability_zones :
        contains(data.aws_availability_zones.available.names, az)
      ])
      error_message = "Every configured Availability Zone must be available in the selected AWS region."
    }

    precondition {
      condition     = local.subnet_cidrs_within_vpc
      error_message = "Every public, private-application, and private-data subnet CIDR must fit inside vpc_cidr."
    }

    precondition {
      condition     = local.subnet_cidrs_are_non_overlapping
      error_message = "Public, private-application, and private-data subnet CIDRs must not overlap."
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
    Tier = "network"
  })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${each.value.az}"
    Tier = "public"
  })
}

resource "aws_subnet" "private_application" {
  for_each = local.private_application_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-app-${each.value.az}"
    Tier = "private-application"
  })
}

resource "aws_subnet" "private_data" {
  for_each = local.private_data_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-data-${each.value.az}"
    Tier = "private-data"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
    Tier = "network"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-public"
    Tier = "public"
  })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-eip"
    Tier = "network"
  })
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public["0"].id

  depends_on = [
    aws_internet_gateway.this,
    aws_route_table_association.public,
  ]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat"
    Tier = "network"
  })
}

resource "aws_route_table" "private_application" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-private-app"
    Tier = "private-application"
  })
}

resource "aws_route" "private_application_default" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private_application.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private_application" {
  for_each = aws_subnet.private_application

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_application.id
}

resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-private-data"
    Tier = "private-data"
  })
}

resource "aws_route_table_association" "private_data" {
  for_each = aws_subnet.private_data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_data.id
}
