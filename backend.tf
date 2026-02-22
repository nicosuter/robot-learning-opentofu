# Remote state backend — S3 + DynamoDB locking.
#
# Bootstrap the bucket and lock table ONCE before `tofu init`:
#
#   tofu -chdir=modules/aws/bootstrap init
#   tofu -chdir=modules/aws/bootstrap apply \
#     -var="state_bucket_name=<bucket>" \
#     -var="region=eu-central-1"
#
# Then initialise the root module with the values from bootstrap output:
#
#   tofu init \
#     -backend-config="bucket=<state-bucket-name>" \
#     -backend-config="dynamodb_table=<lock-table-name>"
#
# Partial configuration — bucket and dynamodb_table are supplied via
# -backend-config flags at `tofu init` time so secrets stay out of code.

terraform {
  backend "s3" {
    key     = "ethrc-rbtl/eks/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}
