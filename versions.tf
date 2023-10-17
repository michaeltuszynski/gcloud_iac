terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.1"
    }
    github = {
      source = "integrations/github"
    }
    # google-beta = {
    #   source  = "hashicorp/google-beta"
    #   version = "~> 3.0"
    # }
  }
}

provider "google" {
  #credentials = file("terraform-admin-402218-d12b6eae1339.json")
  credentials = file("gcp-creds-v2.json")
  region      = "us-central1"
  zone        = "us-central1-a"
}

# provider "google-beta" {
#   credentials = file("terraform-admin-402218-d12b6eae1339.json")
#   project     = "terraform-admin-402218"
#   region      = "us-central1"
#   zone = "us-central1-a"
# }

provider "github" {
  token = var.github_token
  owner = var.github_username
}

provider "random" {}

