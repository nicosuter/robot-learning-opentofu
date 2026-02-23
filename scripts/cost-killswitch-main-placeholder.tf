variable "private_route_table_id" {
  description = "The ID of the private route table routing traffic to the NAT Gateway"
  type        = string
}

variable "alert_email" {
  description = "Email to notify when the kill-switch triggers"
  type        = string
}

# 1. IAM Role & Permissions for Lambda
resource "aws_iam_role" "nat_kill_switch_role" {
  name = "nat-kill-switch-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "nat_kill_switch_policy" {
  name = "nat-kill-switch-policy"
  role = aws_iam_role.nat_kill_switch_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ec2:DeleteRoute", "ec2:DescribeRouteTables"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# 2. Package and Deploy the Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/kill_switch.py"
  output_path = "${path.module}/kill_switch.zip"
}

resource "aws_lambda_function" "nat_kill_switch" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "nat-billing-kill-switch"
  role             = aws_iam_role.nat_kill_switch_role.arn
  handler          = "kill_switch.lambda_handler"
  runtime          = "python3.10"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      ROUTE_TABLE_ID = var.private_route_table_id
    }
  }
}

# 3. SNS Topic for Budget Alerts
resource "aws_sns_topic" "budget_alerts" {
  name = "nat-budget-alerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "lambda_trigger" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.nat_kill_switch.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nat_kill_switch.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.budget_alerts.arn
}

# 4. AWS Budget for EC2 Data Transfer Out
resource "aws_budgets_budget" "nat_data_transfer" {
  name              = "NAT-Gateway-Data-Transfer-Limit"
  budget_type       = "COST"
  limit_amount      = "50.0"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-02-01_00:00"

  cost_filter {
    name = "Service"
    values = ["Amazon Elastic Compute Cloud - Compute"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }
}