variable "cidr" {
  type        = string
  default     = "10.179.0.0/20"
  description = "Network range for created virtual network."
}

variable "no_public_ip" {
  type        = bool
  default     = true
  description = "Defines whether Secure Cluster Connectivity (No Public IP) should be enabled."
}

variable "region" {
  type    = string
}

variable "project_name" {
  type        = string
}

resource "random_string" "naming" {
  special = false
  upper   = false
  length  = 6
}

