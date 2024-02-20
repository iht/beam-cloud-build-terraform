variable "beam_repo" {
  description = "Git repo reference for your Beam fork (Github fork)"
  type        = string
}

variable "container_repo" {
  description = "Git repo reference for the container code (Github fork)"
  type        = string
}

variable "github_owner" {
  description = "Name of owner of the Github forks used (normally, your username)"
  type        = string
}

variable "project_id" {
  description = "Project id (existing project)"
  type        = string
}

variable "region" {
  description = "The region for the Cloud Build triggers (global or GCE region)"
  type        = string
}
