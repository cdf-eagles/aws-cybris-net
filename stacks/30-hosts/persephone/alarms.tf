# The alarm and the recovery notice both publish to the account alert topic.
resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  alarm_name          = "${local.host_name}-status-check-failed"
  alarm_description   = "StatusCheckFailed on ${local.host_name}: the system or instance status check failed."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    InstanceId = aws_instance.this.id
  }

  alarm_actions = [local.account.account_alerts_topic_arn]
  ok_actions    = [local.account.account_alerts_topic_arn]
}
