import {
  to = aws_ce_anomaly_monitor.services
  id = "arn:${data.aws_partition.current.partition}:ce::${local.account_id}:anomalymonitor/5a2080e6-5306-4c04-8f4a-566ac732ff61"
}

import {
  to = aws_ce_anomaly_subscription.services
  id = "arn:${data.aws_partition.current.partition}:ce::${local.account_id}:anomalysubscription/664dc9aa-1e03-416b-8839-e49c18b3e7aa"
}
