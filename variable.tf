variable "subscription_id" {
  description = "The Azure Subscription ID"
  type        = string
}

variable "client_id" {
  description = "The Azure Client ID"
  type        = string
}

variable "client_secret" {
  description = "The Azure Client Secret"
  type        = string
}

variable "tenant_id" {
  description = "The Azure Tenant ID"
  type        = string
}

variable "tls_cert_file" {
  description = "Path to the TLS certificate file"
}

variable "tls_key_file" {
  description = "Path to the TLS key file"
}
