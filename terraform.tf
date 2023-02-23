terraform {
  required_version = ">=1.3.7"
  required_providers {
    nifcloud = {
      source  = "nifcloud/nifcloud"
      version = ">= 1.7.0, < 2.0.0"
    }
  }
}