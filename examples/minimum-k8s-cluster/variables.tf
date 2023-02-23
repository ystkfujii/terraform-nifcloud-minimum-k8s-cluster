variable "instance_key_name" {
  description = "The key name of the Key Pair to use for the instance"
  type        = string
  default     = "deployerkey"
}


variable "working_server_ip" {
  description = "The ip address of working server"
  type        = string
}