mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }
}

run "accepts_valid_non_overlapping_subnets" {
  command = plan

  variables {
    name_prefix = "dcc-network-test"
    vpc_cidr    = "10.81.0.0/16"

    availability_zones = [
      "us-east-1a",
      "us-east-1b",
    ]

    public_subnet_cidrs = [
      "10.81.0.0/24",
      "10.81.1.0/24",
    ]

    private_application_subnet_cidrs = [
      "10.81.16.0/20",
      "10.81.32.0/20",
    ]

    private_data_subnet_cidrs = [
      "10.81.48.0/24",
      "10.81.49.0/24",
    ]

    enable_nat_gateway = false
  }

  assert {
    condition     = local.subnet_cidrs_within_vpc
    error_message = "All subnet ranges should be contained by the VPC CIDR."
  }

  assert {
    condition     = local.subnet_cidrs_are_non_overlapping
    error_message = "All subnet ranges should be mutually non-overlapping."
  }
}

run "rejects_subnet_outside_vpc" {
  command = plan

  variables {
    name_prefix = "dcc-network-test"
    vpc_cidr    = "10.81.0.0/16"

    availability_zones = [
      "us-east-1a",
      "us-east-1b",
    ]

    public_subnet_cidrs = [
      "10.82.0.0/24",
      "10.81.1.0/24",
    ]

    private_application_subnet_cidrs = [
      "10.81.16.0/20",
      "10.81.32.0/20",
    ]

    private_data_subnet_cidrs = [
      "10.81.48.0/24",
      "10.81.49.0/24",
    ]

    enable_nat_gateway = false
  }

  expect_failures = [
    aws_vpc.this,
  ]
}

run "rejects_overlapping_subnets" {
  command = plan

  variables {
    name_prefix = "dcc-network-test"
    vpc_cidr    = "10.81.0.0/16"

    availability_zones = [
      "us-east-1a",
      "us-east-1b",
    ]

    public_subnet_cidrs = [
      "10.81.0.0/24",
      "10.81.0.128/25",
    ]

    private_application_subnet_cidrs = [
      "10.81.16.0/20",
      "10.81.32.0/20",
    ]

    private_data_subnet_cidrs = [
      "10.81.48.0/24",
      "10.81.49.0/24",
    ]

    enable_nat_gateway = false
  }

  expect_failures = [
    aws_vpc.this,
  ]
}

run "rejects_unavailable_availability_zone" {
  command = plan

  variables {
    name_prefix = "dcc-network-test"
    vpc_cidr    = "10.81.0.0/16"

    availability_zones = [
      "us-east-1a",
      "us-east-1z",
    ]

    public_subnet_cidrs = [
      "10.81.0.0/24",
      "10.81.1.0/24",
    ]

    private_application_subnet_cidrs = [
      "10.81.16.0/20",
      "10.81.32.0/20",
    ]

    private_data_subnet_cidrs = [
      "10.81.48.0/24",
      "10.81.49.0/24",
    ]

    enable_nat_gateway = false
  }

  expect_failures = [
    aws_vpc.this,
  ]
}
