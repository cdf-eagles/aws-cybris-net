resource "aws_guardduty_detector" "this" {
  enable                       = true
  finding_publishing_frequency = "SIX_HOURS"
}

# Only the foundational data sources (CloudTrail, VPC flow, DNS); the
# protection plans bill per resource and this account has one instance.
resource "aws_guardduty_detector_feature" "disabled" {
  for_each = toset(local.guardduty_disabled_features)

  detector_id = aws_guardduty_detector.this.id
  name        = each.value
  status      = "DISABLED"

  dynamic "additional_configuration" {
    for_each = each.value == "RUNTIME_MONITORING" ? local.guardduty_runtime_sub_features : []

    content {
      name   = additional_configuration.value
      status = "DISABLED"
    }
  }
}

# The other allowed regions get the same detector. Their findings are read in
# the console or the API; the alert rule below covers the home region only,
# because an EventBridge rule can target a topic in its own region alone.
resource "aws_guardduty_detector" "us_east_2" {
  provider = aws.us_east_2

  enable                       = true
  finding_publishing_frequency = "SIX_HOURS"
}

resource "aws_guardduty_detector_feature" "us_east_2_disabled" {
  provider = aws.us_east_2
  for_each = toset(local.guardduty_disabled_features)

  detector_id = aws_guardduty_detector.us_east_2.id
  name        = each.value
  status      = "DISABLED"

  dynamic "additional_configuration" {
    for_each = each.value == "RUNTIME_MONITORING" ? local.guardduty_runtime_sub_features : []

    content {
      name   = additional_configuration.value
      status = "DISABLED"
    }
  }
}

resource "aws_guardduty_detector" "us_west_2" {
  provider = aws.us_west_2

  enable                       = true
  finding_publishing_frequency = "SIX_HOURS"
}

resource "aws_guardduty_detector_feature" "us_west_2_disabled" {
  provider = aws.us_west_2
  for_each = toset(local.guardduty_disabled_features)

  detector_id = aws_guardduty_detector.us_west_2.id
  name        = each.value
  status      = "DISABLED"

  dynamic "additional_configuration" {
    for_each = each.value == "RUNTIME_MONITORING" ? local.guardduty_runtime_sub_features : []

    content {
      name   = additional_configuration.value
      status = "DISABLED"
    }
  }
}

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-findings"
  description = "GuardDuty findings of medium severity and above."

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_findings" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "account-alerts"
  arn       = aws_sns_topic.account_alerts.arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      type        = "$.detail.type"
      description = "$.detail.description"
      region      = "$.region"
    }
    input_template = "\"GuardDuty <type> (severity <severity>) in <region>: <description>\""
  }
}

# RDS_LOGIN_EVENTS stays disabled in all three detectors, in resources of its
# own: GuardDuty now returns an RDS_DATA_RISK sub-feature under it, which the
# provider does not accept in additional_configuration, so the plan would
# otherwise offer to remove it on every run. Only its sub-features are ignored.
resource "aws_guardduty_detector_feature" "rds_login_disabled" {
  detector_id = aws_guardduty_detector.this.id
  name        = "RDS_LOGIN_EVENTS"
  status      = "DISABLED"

  lifecycle {
    ignore_changes = [additional_configuration]
  }
}

resource "aws_guardduty_detector_feature" "us_east_2_rds_login_disabled" {
  provider = aws.us_east_2

  detector_id = aws_guardduty_detector.us_east_2.id
  name        = "RDS_LOGIN_EVENTS"
  status      = "DISABLED"

  lifecycle {
    ignore_changes = [additional_configuration]
  }
}

resource "aws_guardduty_detector_feature" "us_west_2_rds_login_disabled" {
  provider = aws.us_west_2

  detector_id = aws_guardduty_detector.us_west_2.id
  name        = "RDS_LOGIN_EVENTS"
  status      = "DISABLED"

  lifecycle {
    ignore_changes = [additional_configuration]
  }
}

moved {
  from = aws_guardduty_detector_feature.disabled["RDS_LOGIN_EVENTS"]
  to   = aws_guardduty_detector_feature.rds_login_disabled
}

moved {
  from = aws_guardduty_detector_feature.us_east_2_disabled["RDS_LOGIN_EVENTS"]
  to   = aws_guardduty_detector_feature.us_east_2_rds_login_disabled
}

moved {
  from = aws_guardduty_detector_feature.us_west_2_disabled["RDS_LOGIN_EVENTS"]
  to   = aws_guardduty_detector_feature.us_west_2_rds_login_disabled
}
