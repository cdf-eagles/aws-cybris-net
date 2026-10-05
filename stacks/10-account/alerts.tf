resource "aws_sns_topic" "account_alerts" {
  name = "account-alerts"
}

data "aws_iam_policy_document" "account_alerts" {
  statement {
    sid       = "AllowAccountServicesToPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.account_alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "budgets.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "account_alerts" {
  arn    = aws_sns_topic.account_alerts.arn
  policy = data.aws_iam_policy_document.account_alerts.json
}

resource "aws_sns_topic_subscription" "account_alerts_email" {
  topic_arn = aws_sns_topic.account_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_budgets_budget" "monthly" {
  name         = "Cybris.Net Budget"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_tax                = true
    include_subscription       = true
    use_blended                = false
    include_refund             = false
    include_credit             = false
    include_upfront            = true
    include_recurring          = true
    include_other_subscription = true
    include_support            = true
    include_discount           = true
    use_amortized              = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 85
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  lifecycle {
    ignore_changes = [time_period_start]
  }
}
