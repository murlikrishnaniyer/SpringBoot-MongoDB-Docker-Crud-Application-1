variable "github_repository" {
  description = "GitHub repository in owner/name format."
  type        = string
  default     = "murlikrishnaniyer/SpringBoot-MongoDB-Docker-Crud-Application-1"
}

variable "jenkins_url" {
  description = "Public HTTPS base URL for the Jenkins server."
  type        = string
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
}

variable "github_webhook_secret" {
  description = "Shared secret used to sign GitHub webhook deliveries; keep Terraform state encrypted."
  type        = string
  sensitive   = true
}

variable "jenkins_scm_credentials_id" {
  description = "Existing Jenkins credential ID for cloning a private GitHub repository; leave empty for public repositories."
  type        = string
  default     = ""
}
