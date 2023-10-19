resource "random_pet" "project_id" {
  length    = 2
  separator = "-"
}

resource "google_project_service" "services" {
  project = var.project_id
  for_each = toset([
    "run.googleapis.com",
    "compute.googleapis.com",
    "containerregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudapis.googleapis.com",
    "servicemanagement.googleapis.com",
    "servicecontrol.googleapis.com",
    "container.googleapis.com",
    "firestore.googleapis.com",
    "iam.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

resource "google_service_account" "application_sa" {
  account_id   = "terraform"
  display_name = "created-sa-for-app"
  project      = var.project_id
}

resource "google_service_account_key" "application_sa_key" {
  service_account_id = google_service_account.application_sa.name
}

resource "google_artifact_registry_repository" "backend" {
  project       = var.project_name
  location      = var.region
  repository_id = var.repository_name_backend
  description   = "Backend repository"
  format        = "DOCKER"

  docker_config {
    immutable_tags = false
  }
}

resource "google_artifact_registry_repository" "frontend" {
  project       = var.project_name
  location      = var.region
  repository_id = var.repository_name_frontend
  description   = "Frontend repository"
  format        = "DOCKER"

  docker_config {
    immutable_tags = false
  }
}

resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.project_name
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.application_sa.email}"
}

resource "google_project_iam_member" "artifact_registry_writer" {
  project = var.project_name
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.application_sa.email}"
}

//for google cloud run deployments from github actions
resource "google_service_account_iam_binding" "sa_actas_binding" {
  service_account_id = google_service_account.application_sa.name
  role               = "roles/iam.serviceAccountUser"

  members = [
    "serviceAccount:${google_service_account.application_sa.email}"
  ]
}

resource "github_actions_secret" "deployment_secret_backend" {
  repository      = var.repository_name_backend
  secret_name     = "GCP_SA_KEY"
  plaintext_value = base64decode(google_service_account_key.application_sa_key.private_key)
}

resource "github_actions_secret" "deployment_secret_frontend" {
  repository      = var.repository_name_frontend
  secret_name     = "GCP_SA_KEY"
  plaintext_value = base64decode(google_service_account_key.application_sa_key.private_key)
}

resource "github_repository_file" "backend_workflow" {

  depends_on = [github_actions_secret.deployment_secret_backend, google_artifact_registry_repository.backend]

  overwrite_on_create = true
  repository          = var.repository_name_backend
  branch              = var.repository_branch_backend
  file                = ".github/workflows/gcp-workflow.yml"
  content             = <<-EOF
    name: CI/CD Pipeline

    on:
      push:
        branches:
          - ${var.repository_branch_backend}


    jobs:
      push_to_registry:
        name: Build Backend API
        runs-on: ubuntu-latest

        steps:
            - name: Checkout code
              uses: actions/checkout@v2

            - name: Set up Docker Buildx
              uses: docker/setup-buildx-action@v1

            - name: Setup GCP Authentication
              uses: google-github-actions/auth@v1
              with:
                credentials_json: $${{ secrets.GCP_SA_KEY }}

            - name: Login to Artifact Registry
              uses: docker/login-action@v1
              with:
                registry: ${var.region}-docker.pkg.dev
                username: _json_key
                password: $${{ secrets.GCP_SA_KEY }}

            - name: Build and push Docker image
              uses: docker/build-push-action@v2
              with:
                context: .
                file: ./Dockerfile
                push: true
                tags: ${var.region}-docker.pkg.dev/${var.project_name}/${var.repository_name_backend}/${var.repository_name_backend}:latest
            - name: Check if Cloud Run Service Exists
              id: check_service
              run: |
                if gcloud run services describe ${var.prefix}-api --region=${var.region} --platform=managed; then
                  echo "::set-output name=service_exists::true"
                else
                  echo "::set-output name=service_exists::false"
                fi
            - name: Deploy to Cloud Run
              if: steps.check_service.outputs.service_exists == 'true'
              uses: 'google-github-actions/deploy-cloudrun@v1'
              with:
                service: "${var.prefix}-api"
                region: ${var.region}
                image: ${var.region}-docker.pkg.dev/${var.project_name}/${var.repository_name_backend}/${var.repository_name_backend}:latest
    EOF
}

data "http" "dispatch_event_backend" {

  url    = "https://api.github.com/repos/${var.github_username}/${var.repository_name_backend}/dispatches"
  method = "POST"

  request_headers = {
    Accept        = "application/vnd.github.everest-preview+json"
    Authorization = "token ${var.github_token}"
  }

  request_body = jsonencode({
    event_type = "start-my-workflow"
  })

  depends_on = [github_repository_file.backend_workflow]
}


resource "google_secret_manager_secret" "this" {
  project   = var.project_name
  secret_id = "${var.prefix}-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "individual_secret" {
  secret      = google_secret_manager_secret.this.id
  secret_data = base64decode(google_service_account_key.application_sa_key.private_key)
}

# resource "google_secret_manager_secret_iam_member" "secret_accessor" {
#   secret_id = google_secret_manager_secret.this.id
#   role      = "roles/secretmanager.secretAccessor"
#   member    = "serviceAccount:${google_service_account.application_sa.email}"
# }

resource "google_project_iam_member" "secret_access" {
  project = var.project_name
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.application_sa.email}"
}

resource "random_string" "document_id" {
  length  = 20
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "google_firestore_database" "database" {
  project     = var.project_name
  name        = "${random_pet.project_id.id}-db"
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"
}

resource "google_project_iam_member" "firestore_iam" {
  project = var.project_name
  role    = "roles/datastore.owner"
  member  = "serviceAccount:${google_service_account.application_sa.email}"
}

resource "google_cloudfunctions_function" "insert_firestore_doc" {
  name                  = "insert-firestore-doc"
  description           = "Inserts a default document into Firestore"
  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.archive.name
  trigger_http          = true
  runtime               = "python310"
  entry_point           = "main"
  project               = var.project_name
  service_account_email = google_service_account.application_sa.email

  environment_variables = {
    PROJECT_ID      = var.project_id
    COLLECTION_NAME = var.collection_name
    DATABASE_NAME   = google_firestore_database.database.name,
    SECRET_NAME     = google_secret_manager_secret.this.secret_id,
  }
}

resource "google_project_iam_member" "function_invoker" {
  project = var.project_name
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.application_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "function_secret_access" {
  project   = var.project_name
  secret_id = google_secret_manager_secret.this.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.application_sa.email}"
}

resource "google_project_iam_binding" "cloud_function_firestore_writer" {
  project = var.project_name
  role    = "roles/datastore.user"
  members = [
    "serviceAccount:${google_service_account.application_sa.email}"
  ]
}

resource "google_storage_bucket" "bucket" {
  name          = "${var.prefix}-cloud-function-bucket"
  location      = "US"
  force_destroy = true
  project       = var.project_name
}

variable "gcf_insert_firestore_doc_zip" {
  type    = string
  default = "./scripts/insert-firestore-doc/index.zip"
}

resource "null_resource" "delete_old_archive_firestore_doc" {
  provisioner "local-exec" {
    command = "rm -f ${var.gcf_insert_firestore_doc_zip}"
  }
  triggers = {
    always_recreate = "${timestamp()}" # Ensure it runs every time
  }
}

data "archive_file" "gcf_insert_firestore_doc" {
  depends_on  = [null_resource.delete_old_archive_firestore_doc]
  type        = "zip"
  source_dir  = "./scripts/insert-firestore-doc"
  output_path = var.gcf_insert_firestore_doc_zip
}

resource "google_storage_bucket_object" "archive" {
  depends_on = [data.archive_file.gcf_insert_firestore_doc]
  name       = "insert-firestore-doc.zip"
  bucket     = google_storage_bucket.bucket.name
  source     = data.archive_file.gcf_insert_firestore_doc.output_path
}

resource "null_resource" "invoke_function" {
  depends_on = [
    google_cloudfunctions_function.insert_firestore_doc,
    google_firestore_database.database,
    google_secret_manager_secret.this
  ]
  provisioner "local-exec" {
    command = "gcloud functions call ${google_cloudfunctions_function.insert_firestore_doc.name} --region ${var.region}"
  }

  triggers = {
    always_run = "${timestamp()}" # This will always execute the provisioner.
  }
}


resource "null_resource" "destroy_database" {
  triggers = {
    project_name  = var.project_name
    database_name = google_firestore_database.database.name
  }

  provisioner "local-exec" {
    when    = destroy
    command = "gcloud alpha firestore databases delete --database=${self.triggers.database_name} --project=${self.triggers.project_name} --quiet"
  }
}

resource "time_sleep" "wait_for_it" {
  depends_on = [google_artifact_registry_repository.backend, data.http.dispatch_event_backend]

  create_duration = "3m"
}

// Deploy container to Cloud Run
resource "google_cloud_run_service" "api_service" {
  project = var.project_name

  depends_on = [
    time_sleep.wait_for_it,
    #null_resource.check_image,
    github_repository_file.backend_workflow,
    google_firestore_database.database,
    google_artifact_registry_repository.backend,
  ]

  name     = "${var.prefix}-api"
  location = var.region

  template {
    spec {
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_name}/${var.repository_name_backend}/${var.repository_name_backend}:latest"
        ports {
          container_port = var.container_port
        }
        env {
          name  = "NODEPORT"
          value = var.container_port
        }
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "SECRET_NAME"
          value = google_secret_manager_secret.this.secret_id
        }
        env {
          name  = "SECRET_VERSION"
          value = google_secret_manager_secret_version.individual_secret.version
        }
        env {
          name  = "COLLECTION_NAME"
          value = var.collection_name
        }
        env {
          name  = "DATABASE_NAME"
          value = google_firestore_database.database.name
        }
      }
      service_account_name = google_service_account.application_sa.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

resource "google_project_iam_member" "api_service_iam_member" {
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.application_sa.email}"
  project = var.project_name
}

// IAM: Allow unauthenticated access to Cloud Run service
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_service.api_service.name
  location = google_cloud_run_service.api_service.location
  role     = "roles/run.invoker"
  member   = "allUsers"
  project  = var.project_name
}




resource "google_storage_bucket" "static_website_bucket" {
  name          = "${var.prefix}-static-website-bucket"
  location      = "US"
  force_destroy = true
  project       = var.project_name

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}

resource "google_storage_bucket_iam_member" "bucket_iam_member" {
  bucket = google_storage_bucket.static_website_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.application_sa.email}"
}

resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.static_website_bucket.name
  role   = "roles/storage.legacyObjectReader"
  member = "allUsers"
}

# resource "google_storage_bucket_access_control" "public_rule" {
#   bucket = google_storage_bucket.static_website_bucket.id
#   role   = "READER"
#   entity = "allUsers"
# }

resource "github_repository_file" "frontend_workflow" {

  depends_on = [
    github_actions_secret.deployment_secret_frontend,
    google_artifact_registry_repository.frontend,
    google_storage_bucket.static_website_bucket,
    google_cloud_run_service.api_service
  ]


  overwrite_on_create = true
  repository          = var.repository_name_frontend
  branch              = var.repository_branch_frontend
  file                = ".github/workflows/fe-workflow.yml"
  content             = <<-EOF
    name: CI/CD Pipeline

    on:
      push:
        branches:
          - ${var.repository_branch_frontend}


    jobs:
      push_to_gcp_bucket:
        name: Build react website for GCP
        runs-on: ubuntu-latest

        steps:
            - name: Checkout code
              uses: actions/checkout@v3

            - name: Set up Node.js
              uses: actions/setup-node@v3
              with:
                node-version: '18'

            - name: Install dependencies
              run: yarn install

            - name: Build
              run: yarn build

            - name: Create config.json
              run: |
                echo '{
                  "REACT_APP_BACKEND_URL": "${replace(google_cloud_run_service.api_service.status[0].url, "https://", "")}"
                }' > build/config.json

            - name: Setup GCP Authentication
              uses: google-github-actions/auth@v1
              with:
                credentials_json: $${{ secrets.GCP_SA_KEY }}

            - name: Upload build folder to GCP bucket
              uses: 'google-github-actions/upload-cloud-storage@v1'
              with:
                path: 'build'
                destination: '${google_storage_bucket.static_website_bucket.name}'
                parent: false
  EOF
}

data "http" "dispatch_event_frontend" {

  url    = "https://api.github.com/repos/${var.github_username}/${var.repository_name_frontend}/dispatches"
  method = "POST"

  request_headers = {
    Accept        = "application/vnd.github.everest-preview+json"
    Authorization = "token ${var.github_token}"
  }

  request_body = jsonencode({
    event_type = "start-my-workflow"
  })

  depends_on = [github_repository_file.frontend_workflow]
}
