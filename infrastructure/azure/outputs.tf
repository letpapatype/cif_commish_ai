output "databricks_host" {
  value = "https://${azurerm_databricks_workspace.dbx_workspace.workspace_url}"
}

output "databricks_workspace_id" {
  value = azurerm_databricks_workspace.dbx_workspace.id  
}