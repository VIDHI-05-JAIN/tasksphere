variable "region" {
  description = "AWS region (must match the region selected in the AWS console)"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  type    = string
  default = "tasksphere"
}

variable "instance_type" {
  type    = string
  default = "t2.medium"
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

# Leave empty to let Terraform create the IAM role for the CloudWatch agent.
# If your account blocks IAM creation (e.g. a student lab), set this to an existing
# instance profile name such as "LabInstanceProfile".
variable "existing_instance_profile" {
  type    = string
  default = ""
}
