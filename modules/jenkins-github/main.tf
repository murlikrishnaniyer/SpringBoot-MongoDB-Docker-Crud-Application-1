locals {
  webhook_url = "${trimsuffix(var.jenkins_url, "/")}/github-webhook/"
}

resource "jenkins_credential_secret_text" "github_webhook" {
  name        = var.webhook_secret_credential_id
  description = "Shared secret used to validate GitHub webhooks"
  secret      = var.github_webhook_secret
  scope       = "GLOBAL"
}

resource "github_repository_webhook" "jenkins" {
  repository = var.github_repository
  events     = ["push"]
  active     = true

  configuration {
    url          = local.webhook_url
    content_type = "json"
    secret       = var.github_webhook_secret
    insecure_ssl = false
  }
}

resource "jenkins_job" "pipeline" {
  name = var.jenkins_job_name

  template = templatefile("${path.module}/pipeline-job.xml.tftpl", {
    repository_url = "https://github.com/${var.github_repository}.git"
    branch         = var.github_branch
    credentials_id = var.jenkins_scm_credentials_id
  })
}
