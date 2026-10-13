# See infra/global/backend.tf for the one-time bootstrap steps (S3 bucket +
# DynamoDB lock table). Both envs share the same bucket/table, distinguished
# by `key`.

terraform {
  backend "s3" {
    bucket         = "rideflow-tfstate-REPLACE-ME"   # placeholder — see infra/global/backend.tf
    key            = "envs/primary/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "rideflow-tf-locks"
    encrypt        = true
  }
}
