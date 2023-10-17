terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.1"
    }
    github = {
      source = "integrations/github"
    }
  }
}

provider "google" {
  credentials = file("gcp-creds-v2.json")
  region      = "us-central1"
  zone        = "us-central1-a"
}

provider "github" {
  token = var.github_token
  owner = var.github_username
}

provider "random" {}

