# Remote state backend — S3 + DynamoDB locking.
#
# Run once before `tofu init`:
#
#   aws s3api create-bucket \
#     --bucket <your-state-bucket> \
#     --region eu-central-1 \
#     --create-bucket-configuration LocationConstraint=eu-central-1
#
#   aws s3api put-bucket-encryption \
#     --bucket <your-state-bucket> \
#     --server-side-encryption-configuration \
#       '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
#
#   aws s3api put-bucket-versioning \
#     --bucket <your-state-bucket> \
#     --versioning-configuration Status=Enabled
#
#   aws dynamodb create-table \
#     --table-name <your-lock-table> \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST \
#     --region eu-central-1

terraform {
  backend "s3" {
    bucket         = "<your-state-bucket>"
    key            = "ethrc-rbtl/eks/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "<your-lock-table>"
  }
}
