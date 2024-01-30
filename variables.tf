variable "rg_name" {
  type    = string
  default = "rg-apc-tf-meetup"
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "mode_failtest" {
  type    = bool
  default = false
}
