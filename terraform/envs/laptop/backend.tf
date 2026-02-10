# Local backend — state lives in ./state (gitignored)
terraform {
  backend "local" {
    path = "../../../state/terraform.tfstate"
  }
}
