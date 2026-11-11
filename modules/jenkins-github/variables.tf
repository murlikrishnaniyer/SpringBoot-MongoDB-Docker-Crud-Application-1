variable "github_repository" {
  description = "GitHub repository in owner/name format."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in owner/name format."
  }
}

variable "jenkins_url" {
  description = "Public HTTPS base URL for the Jenkins server."
  type        = string

  validation {
    condition     = can(regex("^https://[^/].*", var.jenkins_url))
    error_message = "jenkins_url must be a publicly reachable HTTPS URL."
  }
}

variable "jenkins_job_name" {
  description = "Name of the Pipeline job to create in Jenkins."
  type        = string
  default     = "spring-mongodb-crud-application"
}

variable "github_branch" {
  description = "Branch containing the Jenkinsfile."
  type        = string
  default     = "master"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.github_branch))
    error_message = "github_branch may contain letters, numbers, dots, underscores, hyphens, and slashes."
  }
}

variable "github_webhook_secret" {
  description = "Shared secret used to sign GitHub webhook deliveries; keep Terraform state encrypted."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.github_webhook_secret) >= 32
    error_message = "github_webhook_secret must contain at least 32 characters."
  }
}

variable "webhook_secret_credential_id" {
  description = "Jenkins credential ID for the GitHub webhook validation secret."
  type        = string
  default     = "github-webhook-secret"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+$", var.webhook_secret_credential_id))
    error_message = "webhook_secret_credential_id may contain letters, numbers, dots, underscores, and hyphens."
  }
}

variable "jenkins_scm_credentials_id" {
  description = "Existing Jenkins credential ID for cloning a private GitHub repository; leave empty for public repositories."
  type        = string
  default     = ""
}
