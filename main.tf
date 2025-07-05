terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.35.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.0"
    }
    databricks = {
      source = "databricks/databricks"
      version = "1.84.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "terraform_states"
    storage_account_name = "tfstatestorage0705"
    container_name       = "tfstatecontainer"
    key                  = "terraform.tfstate"

  }
}

provider "azurerm" {
  features {}
}

provider "databricks" {
  host       = module.azurerm_infrastructure.databricks_host
}


variable "region" {
  type    = string
  default = "eastus"
}

variable "project_name" {
  type        = string
  default     = "databricks-ai"
  description = "Name of the project."
}

module "azurerm_infrastructure" {
  source = "./infrastructure/azure"

  region       = var.region
  project_name = var.project_name
  no_public_ip = true
}

module "databricks_workspace" {
  source = "./infrastructure/databricks"
  project_name = var.project_name
  region = var.region
  databricks_workspace_id = module.azurerm_infrastructure.databricks_workspace_id
  depends_on = [module.azurerm_infrastructure]
}

output "databricks_host" {
  value = module.azurerm_infrastructure.databricks_host
}
