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