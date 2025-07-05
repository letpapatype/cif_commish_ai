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

resource "azurerm_databricks_workspace" "dbx_workspace" {
  name                        = "${var.project_name}-workspace"
  resource_group_name         = azurerm_resource_group.dbx_group.name
  location                    = azurerm_resource_group.dbx_group.location
  sku                         = "standard"
  managed_resource_group_name = "${var.project_name}-workspace-rg"
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