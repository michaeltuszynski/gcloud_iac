// Outputs: Display the deployed API URL
output "api_url" {
  description = "The URL of the deployed API."
  value       = google_cloud_run_service.api_service.status[0].url
}

output "website_url" {
  description = "The URL of the static website."
  value       = "https://${google_storage_bucket.static_website_bucket.name}.storage.googleapis.com/index.html"
}