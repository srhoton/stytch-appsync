terraform {
  backend "s3" {
    bucket = "steve-rhoton-tfstate"
    key    = "stytch-appsync/terraform.tfstate"
    region = "us-west-2"
    # No DynamoDB locking table configured
  }
}