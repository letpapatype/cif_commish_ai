variable "project_name" {
  type        = string
  description = "Name of the project."
  
}

variable "region" {
  type        = string
  description = "Azure region for the Databricks workspace."
}

variable "databricks_workspace_id" {
  type        = string
  description = "ID of the Databricks workspace."
}

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account for Unity Catalog."
}

variable "access_connector_id" {
  type        = string
  description = "ID of the Databricks access connector for Unity Catalog."
}

