# Data volumes outlive the instance; 30-hosts attaches them. The root volume
# belongs to the instance and is declared there.
resource "aws_ebs_volume" "data" {
  for_each = local.data_volumes

  availability_zone = "${var.region}a"
  size              = 20
  type              = "gp3"
  iops              = 3000
  throughput        = 125
  encrypted         = true
  kms_key_id        = aws_kms_key.persephone.arn

  tags = {
    Name      = each.value.name
    Protected = "true"
    Backup    = "daily"
  }

  lifecycle {
    prevent_destroy = true
  }
}
