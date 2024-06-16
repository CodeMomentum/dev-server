variable "GITHUB_TOKEN" {
  description = "The GitHub personal access token"
  type        = string
}

variable "RUNNER_NAME" {
  description = "The name of the GitHub runner"
  type        = string
}

variable "RUNNER_REPO" {
  description = "The GitHub repository for the runner"
  type        = string
}

variable "RUNNER_USER" {
  description = "The user for the runner"
  type        = string
  default     = "adminuser"
}
