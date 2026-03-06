# Local backend — deploy management from your machine first.
# After the instance exists, you can run the main Hercules config from it.
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
