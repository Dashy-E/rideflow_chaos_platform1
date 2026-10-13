# See infra/global/backend.tf for the one-time bootstrap steps (S3 bucket +
# DynamoDB lock table). State is stored in the PRIMARY region's bucket per
# doc §7.4 ("State is stored in S3 with DynamoDB locking, in the primary
# region only") — only the `key` differs between envs.

terraform {
  backend "s3" {
    bucket         = "rideflow-tfstate-REPLACE-ME"   # placeholder — see infra/global/backend.tf
    key            = "envs/secondary/terraform.tfstate"
    region         = "ap-south-1"                     # primary region, intentionally — see comment above
    dynamodb_table = "rideflow-tf-locks"
    encrypt        = true
  }
}
