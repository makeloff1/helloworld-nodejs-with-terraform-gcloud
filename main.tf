terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.34.0"
    }
  }
}

provider "google" {
  credentials = file("~/.gcp/pragmatic-ruler-400608-b729284056ec.json")
  project = "pragmatic-ruler-400608"
  region = "us-central1"
}

resource "random_id" "default" {
  byte_length = 8
}

# bucket for zip
resource "google_storage_bucket" "default" {
  name                        = "${random_id.default.hex}-morita-gcf-source" # Every bucket name must be globally unique
  location                    = "US"
  uniform_bucket_level_access = true
}

# zip
data "archive_file" "default" {
  type        = "zip"
  output_path = "./function-source.zip"
  source_dir  = "."
}

# upload zip
resource "google_storage_bucket_object" "object" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.default.name
  source = data.archive_file.default.output_path # Add path to the zipped function source code
}

# cloud function
resource "google_cloudfunctions2_function" "default" {
  name        = "function-v2"
  location    = "us-central1"
  description = "a new function"

  build_config {
    runtime     = "nodejs16"
    entry_point = "helloHttp" # Set the entry point
    source {
      storage_source {
        bucket = google_storage_bucket.default.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 60
  }
}

# 認証無しでHTTPアクセス
# 以下がない場合、
# gcloud functions describe function-v2 --gen2 --region=us-central1 --format="value(serviceConfig.uri)"
# curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" <YOUR_FUNCTION_URL> でのアクセスが必要
# https://github.com/hashicorp/terraform-provider-google/issues/5833
# Note google_cloudfunctions2_function_iam_member doesnt work, it has to be google_cloud_run_service_iam_binding
resource "google_cloud_run_service_iam_member" "member" {
  location	= google_cloudfunctions2_function.default.location
  service	= google_cloudfunctions2_function.default.name

  role   = "roles/run.invoker"
  member = "allUsers"
}

output "function_uri" {
  value = google_cloudfunctions2_function.default.service_config[0].uri
}
