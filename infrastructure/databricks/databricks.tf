data "databricks_node_type" "smallest" {
  local_disk = true
}

data "databricks_spark_version" "latest_lts" {
  long_term_support = true
}

resource "databricks_cluster" "shared_autoscaling_cluster" {
  cluster_name            = "${var.project_name}-shared-autoscaling-cluster"
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

# resource "databricks_vector_search_endpoint" "this" {
#   name          = "vector-search-test"
#   endpoint_type = "STANDARD"
# }

# resource "databricks_vector_search_index" "sync" {
#   name          = "main.default.vector_search_index"
#   endpoint_name = databricks_vector_search_endpoint.this.name
#   primary_key   = "id"
#   index_type    = "DELTA_SYNC"
#   delta_sync_index_spec {
#     source_table  = "main.default.source_table"
#     pipeline_type = "TRIGGERED"
#     embedding_source_columns {
#       name                          = "text"
#       embedding_model_endpoint_name = databricks_model_serving.this.name
#     }
#   }
# }