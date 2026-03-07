# Remote state backend — S3 + DynamoDB locking.
#
# Bootstrap the bucket and lock table ONCE before `tofu init`:
#
#   tofu -chdir=modules/aws/bootstrap init
#   tofu -chdir=modules/aws/bootstrap apply \
#     -var="state_bucket_name=<bucket>" \
#     -var="region=us-east-1"
#
# Then initialise the root module (local dev, named profile):
#
#   tofu init -reconfigure \
#     -backend-config="bucket=ethrc-tf" \
#     -backend-config="profile=ethrc"
#
# CI passes bucket, dynamodb_table, and omits profile so the S3 backend
# falls through to the environment-variable credential chain.

terraform {
  backend "s3" {
    key     = "hercules/eks/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
