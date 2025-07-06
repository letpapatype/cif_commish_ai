output "databricks_host" {
  value = "https://${azurerm_databricks_workspace.dbx_workspace.workspace_url}"
}

output "databricks_workspace_id" {
  value = azurerm_databricks_workspace.dbx_workspace.id  
}

output "unity_catalog_storage_account_name" {
  value = azurerm_storage_account.unity_catalog.name
}

output "unity_catalog_access_connector_id" {
  value = azurerm_databricks_access_connector.unity_catalog.id
}