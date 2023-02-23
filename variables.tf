variable "availability_zone" {
  description = "The availability zone"
  type        = string
}

variable "prefix" {
  description = "The prefix for the entire cluster"
  type        = string
  default     = "001"
  validation {
    condition     = length(var.prefix) == 3
    error_message = "Must be a 3 charactor long."
  }
}

variable "private_network_subnet" {
  description = "The subnet of private network"
  type        = string
  default     = "192.168.20.0"
  validation {
    condition     = can(cidrnetmask("${var.private_network_subnet}/24"))
    error_message = "Must be a valid IPv4 CIDR block address."
  }
}

variable "instance_key_name" {
  description = "The key name of the Key Pair to use for the instance"
  type        = string
}

variable "k8s_version" {
  type    = string
  default = "1.26.1-00"
}

variable "containerd_version" {
  type    = string
  default = "1.6.18"
}

variable "instance_count_wk" {
  description = "Number of worker to be created"
  type        = number
  default     = 2
}

variable "instance_type_wk" {
  description = "The instance type of worker"
  type        = string
  default     = "e-large"
}

variable "instance_type_cp" {
  description = "The instance type of control plane"
  type        = string
  default     = "e-large"
}

variable "accounting_type" {
  type    = string
  default = "1"
  validation {
    condition = anytrue([
      var.accounting_type == "1", // Monthly
      var.accounting_type == "2", // Pay per use
    ])
    error_message = "Must be a 1 or 2."
  }
}