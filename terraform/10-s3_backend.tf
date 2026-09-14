terraform {
  backend "s3" {
    bucket = "mentis-backend-bucket"
    key    = "tech_challenge2/terraform/terraform.tfstate"
    region = "us-east-1"
    use_lockfile = true
  }
}