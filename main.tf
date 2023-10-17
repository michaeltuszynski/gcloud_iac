resource "random_pet" "project_id" {
  length    = 2
  separator = "-"
}

// Enable necessary services
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
    "appengine.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}

resource "google_project_iam_member" "admin_sa_owner" {
  project = var.project_id
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.admin_sa.email}"
}

resource "google_service_account" "admin_sa" {
  account_id   = "terraform"
  display_name = "created-sa-for-admin"
  project      = var.project_id
}

resource "google_service_account_key" "admin_sa_key" {
  service_account_id = google_service_account.admin_sa.name
  #public_key_type    = "TYPE_X509_PEM_FILE"
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

resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.project_name
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.admin_sa.email}"
}

resource "google_project_iam_member" "artifact_registry_writer" {
  project = var.project_name
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.admin_sa.email}"
}

resource "github_actions_secret" "deployment_secret" {
  repository      = var.repository_name_backend
  secret_name     = "GCP_SA_KEY"
  plaintext_value = base64decode(google_service_account_key.admin_sa_key.private_key)
}

resource "github_repository_file" "backend_workflow" {

  depends_on = [github_actions_secret.deployment_secret, google_artifact_registry_repository.backend]

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
        name: Build and push Docker image
        runs-on: ubuntu-latest

        steps:
            - name: Checkout code
              uses: actions/checkout@v2

            - name: Set up Docker Buildx
              uses: docker/setup-buildx-action@v1

            - name: Set up Google Cloud SDK
              uses: google-github-actions/setup-gcloud@v1
              with:
                service_account_key: $${{ secrets.GCP_SA_KEY }}
                project_id: ${var.project_name}
                export_default_credentials: true

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
    event_type = "my-event"
  })

  depends_on = [github_repository_file.backend_workflow]
}

// Create a VPC
resource "google_compute_network" "vpc" {
  project                 = var.project_name
  name                    = "my-vpc"
  auto_create_subnetworks = false
}

// Create a public subnet
resource "google_compute_subnetwork" "public_subnet" {
  project       = var.project_name
  name          = "public-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.name
}

// Create a private subnet
resource "google_compute_subnetwork" "private_subnet" {
  project                  = var.project_name
  name                     = "private-subnet"
  ip_cidr_range            = "10.0.2.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.name
  private_ip_google_access = true
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
  secret_data = base64decode(google_service_account_key.admin_sa_key.private_key)
}

resource "google_secret_manager_secret_iam_member" "secret_accessor" {
  secret_id = google_secret_manager_secret.this.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.admin_sa.email}"
}

resource "google_project_iam_member" "secret_access" {
  project = var.project_name
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.admin_sa.email}"
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
  name        = "(default)"
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"
}

resource "google_firestore_document" "mydoc" {
  depends_on  = [google_firestore_database.database]
  project     = var.project_id
  collection  = var.collection_name
  document_id = random_string.document_id.result
  //fields      = "{\"todo\":{\"mapValue\":{\"fields\":{\"title\":{\"stringValue\":\"This is a task\"},\"completed\":{\"booleanValue\":false}}}}}"
  fields      = "{\"title\":{\"stringValue\":\"This is another task\"},\"completed\":{\"booleanValue\":true}}"
}


# resource "null_resource" "destroy_database" {
#   triggers = {
#     resource_name = "${var.prefix}-${random_pet.project_id.id}"
#     project_name  = var.project_name
#     region        = var.region
#   }

#   provisioner "local-exec" {
#     when    = destroy
#     command = "gcloud alpha firestore databases delete --database=${self.triggers.resource_name} --project=${self.triggers.project_name} --quiet"
#   }
# }

resource "time_sleep" "wait_3_mins" {
  depends_on = [google_artifact_registry_repository.backend, data.http.dispatch_event_backend]

  create_duration = "3m"
}


// Deploy container to Cloud Run
resource "google_cloud_run_service" "api_service" {
  project = var.project_name

  depends_on = [
    time_sleep.wait_3_mins,
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
      }
      service_account_name = google_service_account.admin_sa.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

// IAM: Allow unauthenticated access to Cloud Run service
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_service.api_service.name
  location = google_cloud_run_service.api_service.location
  role     = "roles/run.invoker"
  member   = "allUsers"
  project  = var.project_name
}


