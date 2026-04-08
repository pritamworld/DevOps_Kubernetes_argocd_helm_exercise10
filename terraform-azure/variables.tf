variable "resource_group_name" {
  default = "ci-cd-lab-rg"
}

variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "Canada Central"
}

variable "vm_size" {
  default = "Standard_B2s"
}

variable "admin_username" {
  default = "azureuser"
}

variable "public_key" {
  description = "SSH public key for VM access"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B1s"
}

variable "allow_cidr" {
  description = "CIDR allowed to access services (use your IP/CIDR for security; 0.0.0.0/0 for labs)."
  type        = string
  default     = "0.0.0.0/0"
}