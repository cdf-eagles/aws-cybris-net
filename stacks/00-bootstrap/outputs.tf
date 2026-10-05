output "state_bucket_name" {
  description = "Bucket that every other stack names in its backend block."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the state bucket, for the permission sets that read or write state."
  value       = aws_s3_bucket.state.arn
}
