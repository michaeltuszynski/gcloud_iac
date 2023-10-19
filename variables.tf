variable "repository_name_backend" {
  description = "The name of the backend repository"
  type        = string
}

variable "repository_name_frontend" {
  description = "The name of the frontend repository"
  type        = string
}

variable "repository_branch_backend" {
  description = "The name of the backend repository branch"
  type        = string
}

variable "repository_branch_frontend" {
  description = "The name of the frontend repository branch"
  type        = string
}

variable "github_username" {
  description = "The name of the GitHub user"
  type        = string
}

variable "github_token" {
  description = "The GitHub token"
  type        = string
}

variable "region" {
  description = "The region to deploy to"
  type        = string
  default     = "us-central1"
}

variable "container_port" {
  description = "The port the container listens on"
  type        = number
  default     = 5000
}

variable "prefix" {
  description = "The prefix to use for all resources"
  type        = string
  default     = "todoapp"
}

variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "collection_name" {
  description = "The name of the collection"
  type        = string
  default     = "todos"
}