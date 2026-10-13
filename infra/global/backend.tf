# Remote state for global resources (Route 53 zone, IAM, ECR).
#
# Before first `terraform init` here, create the bucket + lock table once,
# by hand or with a tiny bootstrap script (do NOT manage them with this same
# Terraform state — a backend can't create the thing it lives in):
#
#   aws s3api create-bucket --bucket rideflow-tfstate-<your-unique-suffix> \
#     --region ap-south-1 --create-bucket-configuration LocationConstraint=ap-south-1
#   aws s3api put-bucket-versioning --bucket rideflow-tfstate-<your-unique-suffix> \
#     --versioning-configuration Status=Enabled
#   aws dynamodb create-table --table-name rideflow-tf-locks \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST --region ap-south-1
#
# Then replace the placeholder bucket name below with the one you created.

terraform {
  backend "s3" {
    bucket         = "rideflow-tfstate-REPLACE-ME"   # placeholder — see comment above
    key            = "global/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "rideflow-tf-locks"
    encrypt        = true
  }
}
