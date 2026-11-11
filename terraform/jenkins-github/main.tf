provider "github" {}

provider "jenkins" {
  server_url = var.jenkins_url
}

module "jenkins_github" {
  source = "../../modules/jenkins-github"

  github_repository          = var.github_repository
  jenkins_url                = var.jenkins_url
  jenkins_job_name           = var.jenkins_job_name
  github_branch              = var.github_branch
  github_webhook_secret      = var.github_webhook_secret
  jenkins_scm_credentials_id = var.jenkins_scm_credentials_id
}

output "webhook_url" {
  value       = module.jenkins_github.webhook_url
  description = "GitHub webhook endpoint configured for Jenkins."
}

output "jenkins_job_name" {
  value       = module.jenkins_github.jenkins_job_name
  description = "Pipeline job created in Jenkins."
}

output "jenkins_github_plugin_casc_fragment" {
  value       = module.jenkins_github.jenkins_github_plugin_casc_fragment
  description = "Add this fragment to Jenkins Configuration as Code to enable webhook signature validation."
}
