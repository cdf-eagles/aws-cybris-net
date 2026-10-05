output "permission_set_arns" {
  description = "Permission set ARNs by key, for the plan and apply workflows' documentation."
  value       = local.permission_sets
}

output "gha_freebsd_cloud_img_publish_role_arn" {
  description = "Role the freebsd-cloud-img publish jobs assume through OIDC."
  value       = aws_iam_role.gha_freebsd_cloud_img_publish.arn
}

output "gha_aws_cybris_net_plan_role_arn" {
  description = "Role the aws-cybris-net Plan workflow assumes through OIDC."
  value       = aws_iam_role.gha_aws_cybris_net_plan.arn
}

output "account_alerts_topic_arn" {
  description = "SNS topic that budget and GuardDuty alerts publish to."
  value       = aws_sns_topic.account_alerts.arn
}

output "logs_bucket_name" {
  description = "Bucket that holds the CloudTrail logs."
  value       = aws_s3_bucket.logs.id
}

output "engineer_lead_policy_arn" {
  description = "Customer-managed policy shared by the EngineerLead permission set and the CI apply role."
  value       = aws_iam_policy.engineer_lead.arn
}
