locals {
  casc_fragment = join("\n", [
    "unclassified:",
    "  githubpluginconfig:",
    "    hookUrl: \"${local.webhook_url}\"",
    "    hookSecretConfigs:",
    "      - credentialsId: \"${jenkins_credential_secret_text.github_webhook.name}\"",
    "        signatureAlgorithm: SHA256",
  ])
}

output "webhook_url" {
  description = "GitHub webhook endpoint configured for this Jenkins server."
  value       = local.webhook_url
}

output "jenkins_job_name" {
  description = "Name of the Jenkins Pipeline job created by this module."
  value       = jenkins_job.pipeline.name
}

output "jenkins_github_plugin_casc_fragment" {
  description = "Jenkins Configuration as Code fragment to enable webhook signature validation."
  value       = local.casc_fragment
}
