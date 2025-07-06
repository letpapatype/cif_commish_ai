data "databricks_node_type" "smallest" {
  local_disk = true
}

data "databricks_spark_version" "latest_lts" {
  long_term_support = true
}

resource "databricks_catalog" "this" {
  name    = "docs"
  comment = "Catalog for AI and PDF embedding workspace"
  
  # Add storage location for managed catalog
  storage_root = "abfss://unity-catalog@${var.storage_account_name}.dfs.core.windows.net/catalogs/docs"

  depends_on = [databricks_external_location.unity_catalog_location]
}

# Create external location for Unity Catalog storage
resource "databricks_external_location" "unity_catalog_location" {
  name = "unity-catalog-${var.project_name}"
  url  = "abfss://unity-catalog@${var.storage_account_name}.dfs.core.windows.net/"
  
  credential_name = databricks_storage_credential.unity_catalog_credential.name
  comment         = "External location for Unity Catalog storage"
}

# Create storage credential for accessing the storage account
resource "databricks_storage_credential" "unity_catalog_credential" {
  name = "unity-catalog-credential-${var.project_name}"
  
  azure_managed_identity {
    access_connector_id = var.access_connector_id
  }
  
  comment = "Storage credential for Unity Catalog"
}

resource "databricks_schema" "this" {
  catalog_name = databricks_catalog.this.id
  name         = "pdf"
}

resource "databricks_sql_table" "this" {
  name         = "cifembeddings"
  table_type   = "MANAGED"
  catalog_name = databricks_catalog.this.id
  schema_name  = databricks_schema.this.name
  column {
    name = "id"
    type = "STRING"
  }
  column {
    name = "text"
    type = "STRING"
  }
  column {
    name = "embedding"
    type = "ARRAY<FLOAT>"
  }
  column {
    name = "created_at"
    type = "TIMESTAMP"
  }
}

// create a metastore for the storage account as the storage root and assing it to the workspace
resource "databricks_metastore" "this" {
  name = "${var.project_name}_metastore"
  storage_root = "abfss://unity-catalog@${var.storage_account_name}.dfs.core.windows.net/catalogs/docs"
}

resource "databricks_metastore_assignment" "this" {
  metastore_id = databricks_metastore.this.id
  workspace_id = databricks_workspace.dbx_workspace.id
}

resource "databricks_cluster" "shared_autoscaling_cluster" {
  cluster_name            = "${var.project_name}_shared_autoscaling_cluster"
  spark_version           = data.databricks_spark_version.latest_lts.id
  node_type_id            = data.databricks_node_type.smallest.id
  autotermination_minutes = 10
  autoscale {
    min_workers = 0
    max_workers = 5
  }
  spark_conf = {
    "spark.databricks.io.cache.enabled" : true,
    "spark.databricks.io.cache.maxDiskUsage" : "50g",
    "spark.databricks.io.cache.maxMetaDataCache" : "1g"
  }
}

# resource "databricks_job" "this" {
#   name        = "Job with multiple tasks"
#   description = "This job executes multiple tasks on a shared job cluster, which will be provisioned as part of execution, and terminated once all tasks are finished."

#   job_cluster {
#     job_cluster_key = "j"
#     new_cluster {
#       num_workers   = 2
#       spark_version = data.databricks_spark_version.latest.id
#       node_type_id  = data.databricks_node_type.smallest.id
#     }
#   }

#   task {
#     task_key = "a"

#     new_cluster {
#       num_workers   = 1
#       spark_version = data.databricks_spark_version.latest.id
#       node_type_id  = data.databricks_node_type.smallest.id
#     }

#     notebook_task {
#       notebook_path = databricks_notebook.this.path
#     }
#   }
# }

resource "databricks_vector_search_endpoint" "this" {
  name          = "${var.project_name}_vector_search_endpoint"
  endpoint_type = "STANDARD"
}

resource "databricks_vector_search_index" "sync" {
  name          = "${databricks_catalog.this.name}.${databricks_schema.this.name}.${databricks_sql_table.this.name}"
  endpoint_name = databricks_vector_search_endpoint.this.name
  primary_key   = "id"
  index_type    = "DELTA_SYNC"
  
  delta_sync_index_spec {
    source_table  = "${var.project_name}_doc_table"
    pipeline_type = "TRIGGERED"
    embedding_source_columns {
      name                          = "text"
      embedding_model_endpoint_name = "system.ai.bge_base_en_v1_5"
    }
  }
}

output "sql_table_id" {
  value = databricks_sql_table.this.name
}