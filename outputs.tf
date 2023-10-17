// Outputs: Display the deployed API URL
output "api_url" {
  value = google_cloud_run_service.api_service.status[0].url
}
