data "azurerm_client_config" "current" {
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment for the project, e.g., dev, test, prod."
  
}

resource "azurerm_resource_group" "dbx_group" {
  name     = "${var.project_name}-rg"
  location = var.region
  tags     = {
    environment = var.environment
    project     = var.project_name
  }
}

resource "azurerm_virtual_network" "dbx_vnet" {
  name                = "${var.project_name}-vnet"
  resource_group_name = azurerm_resource_group.dbx_group.name
  location            = azurerm_resource_group.dbx_group.location
  address_space       = [var.cidr]
  tags                = {
    environment = var.environment
    project     = var.project_name
  }
}

resource "azurerm_network_security_group" "dbx_nsg" {
  name                = "${var.project_name}-nsg"
  resource_group_name = azurerm_resource_group.dbx_group.name
  location            = azurerm_resource_group.dbx_group.location
  tags                = {
    environment = var.environment
    project     = var.project_name
  }
}

resource "azurerm_subnet" "dbx_public_subnet" {
  name                 = "${var.project_name}-public"
  resource_group_name  = azurerm_resource_group.dbx_group.name
  virtual_network_name = azurerm_virtual_network.dbx_vnet.name
  address_prefixes     = [cidrsubnet(var.cidr, 3, 0)]

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "dbx_public_nsg_association" {
  subnet_id                 = azurerm_subnet.dbx_public_subnet.id
  network_security_group_id = azurerm_network_security_group.dbx_nsg.id
}

resource "azurerm_subnet" "dbx_private_subnet" {
  name                 = "${var.project_name}-private"
  resource_group_name  = azurerm_resource_group.dbx_group.name
  virtual_network_name = azurerm_virtual_network.dbx_vnet.name
  address_prefixes     = [cidrsubnet(var.cidr, 3, 1)]

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "dbx_private_nsg_association" {
  subnet_id                 = azurerm_subnet.dbx_private_subnet.id
  network_security_group_id = azurerm_network_security_group.dbx_nsg.id
}

# Storage account for Unity Catalog
resource "azurerm_storage_account" "unity_catalog" {
  name                     = "unitycatalog${random_string.naming.result}"
  resource_group_name      = azurerm_resource_group.dbx_group.name
  location                 = azurerm_resource_group.dbx_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true # Required for Data Lake Storage Gen2
  
  tags = {
    environment = var.environment
    project     = var.project_name
    purpose     = "unity-catalog"
  }
}

# Container for Unity Catalog
resource "azurerm_storage_container" "unity_catalog" {
  name                 = "unity-catalog"
  storage_account_id   = azurerm_storage_account.unity_catalog.id
  container_access_type = "private"
}

# Create the catalogs directory structure
resource "azurerm_storage_blob" "catalogs_directory" {
  name                   = "catalogs/.keep"
  storage_account_name   = azurerm_storage_account.unity_catalog.name
  storage_container_name = azurerm_storage_container.unity_catalog.name
  type                   = "Block"
  source_content         = "# Directory placeholder for Unity Catalog"
}

# Create the genaiwork catalog directory
resource "azurerm_storage_blob" "genaiwork_directory" {
  name                   = "catalogs/docs/.keep"
  storage_account_name   = azurerm_storage_account.unity_catalog.name
  storage_container_name = azurerm_storage_container.unity_catalog.name
  type                   = "Block"
  source_content         = "# Directory placeholder for genaiwork catalog"
  
  depends_on = [azurerm_storage_blob.catalogs_directory]
}

# Databricks Access Connector for Unity Catalog
resource "azurerm_databricks_access_connector" "unity_catalog" {
  name                = "${var.project_name}-access-connector"
  resource_group_name = azurerm_resource_group.dbx_group.name
  location            = azurerm_resource_group.dbx_group.location
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = {
    environment = var.environment
    project     = var.project_name
    purpose     = "unity-catalog"
  }
}

# Assign Storage Blob Data Contributor role to the access connector
resource "azurerm_role_assignment" "unity_catalog_storage" {
  scope                = azurerm_storage_account.unity_catalog.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.unity_catalog.identity[0].principal_id
}

resource "azurerm_databricks_workspace" "dbx_workspace" {
  name                        = "${var.project_name}_workspace"
  resource_group_name         = azurerm_resource_group.dbx_group.name
  location                    = azurerm_resource_group.dbx_group.location
  sku                         = "premium"
  managed_resource_group_name = "${var.project_name}_workspace_rg"
  tags                        = {
    environment = var.environment
    project     = var.project_name
  }

  custom_parameters {
    no_public_ip                                         = var.no_public_ip
    virtual_network_id                                   = azurerm_virtual_network.dbx_vnet.id
    private_subnet_name                                  = azurerm_subnet.dbx_private_subnet.name
    public_subnet_name                                   = azurerm_subnet.dbx_public_subnet.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.dbx_public_nsg_association.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.dbx_private_nsg_association.id
    storage_account_name = "dbxstoragestorage${random_string.naming.result}"
    storage_account_sku_name = "Standard_LRS"
  }
}

