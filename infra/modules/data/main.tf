# infra/modules/data
#
# DynamoDB tables `users` and `rides` as Global Tables (on-demand billing),
# per doc §6.3/§6.4 attribute schemas and §7.1 resource inventory.
#
# IMPORTANT — Global Table topology:
# A DynamoDB Global Table's replica set is one logical resource shared by
# every region it lives in. Instantiate this module exactly once, from
# infra/envs/primary, with var.replica_regions = ["ap-southeast-1"] (or
# whichever secondary region is in play). Do NOT also instantiate it from
# infra/envs/secondary — that would attempt to create a second, conflicting
# table of the same name. infra/envs/secondary only needs the table name
# (a plain string, identical across regions) to configure app env vars.

locals {
  common_tags = merge(var.tags, {
    "Project" = "rideflow"
    "Module"  = "data"
  })
}

# ---------------------------------------------------------------------------
# users table — doc §6.3
# PK: userId (S). GSI-1 PK: email (S).
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "users" {
  name         = "${var.table_name_prefix}-users"
  billing_mode = var.billing_mode
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI-1-email"
    hash_key        = "email"
    projection_type = "ALL"
  }

  dynamic "replica" {
    for_each = var.replica_regions
    content {
      region_name = replica.value
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  stream_enabled   = length(var.replica_regions) > 0
  stream_view_type = length(var.replica_regions) > 0 ? "NEW_AND_OLD_IMAGES" : null

  tags = merge(local.common_tags, {
    Name = "${var.table_name_prefix}-users"
  })
}

# ---------------------------------------------------------------------------
# rides table — doc §6.4
# PK: rideId (S). GSI-1 PK: userId (S).
# Non-key attributes (state, pickup, drop, fare, surge, driverId, createdAt,
# updatedAt, region) are schemaless in DynamoDB and not declared here.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "rides" {
  name         = "${var.table_name_prefix}-rides"
  billing_mode = var.billing_mode
  hash_key     = "rideId"

  attribute {
    name = "rideId"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI-1-userId"
    hash_key        = "userId"
    projection_type = "ALL"
  }

  dynamic "replica" {
    for_each = var.replica_regions
    content {
      region_name = replica.value
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  stream_enabled   = length(var.replica_regions) > 0
  stream_view_type = length(var.replica_regions) > 0 ? "NEW_AND_OLD_IMAGES" : null

  tags = merge(local.common_tags, {
    Name = "${var.table_name_prefix}-rides"
  })
}
