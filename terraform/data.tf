# Data sources for current AWS environment
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}