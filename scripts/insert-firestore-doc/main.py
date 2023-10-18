import json
import requests
from google.oauth2 import service_account
from google.cloud import secretmanager
from google.auth.transport import requests as gauth_requests
import os

def create_firestore_document(secret_name, project_id, collection_id, database_name, data):

    secret_value = get_secret(secret_name, project_id)

    # Load the service account credentials
    service_account_info = json.loads(secret_value)
    credentials = service_account.Credentials.from_service_account_info(
        service_account_info,
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )

    # Obtain an access token
    request_object = gauth_requests.Request()
    credentials.refresh(request_object)
    access_token = credentials.token

    # Firestore URL
    url = f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/{database_name}/documents/{collection_id}"

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "x-goog-request-params": f"project_id={project_id}&database_id={database_name}"
    }

    response = requests.post(url, headers=headers, data=json.dumps(data))

    return response.json()


def get_secret(secret_id, project_id):
    # Create the Secret Manager client.
    client = secretmanager.SecretManagerServiceClient()

    # Build the resource name of the secret.
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"

    # Get the secret value.
    response = client.access_secret_version(request={"name": name})

    # Return the decoded payload.
    return response.payload.data.decode("UTF-8")

def main(request):
    SECRET_NAME = os.environ.get("SECRET_NAME")
    PROJECT_ID = os.environ.get("PROJECT_ID")
    COLLECTION_ID = os.environ.get("COLLECTION_NAME")
    DATABASE_NAME = os.environ.get("DATABASE_NAME")
    DATA = {
        'fields': {
            'title': {'stringValue': 'This is an example task'},
            'completed': {'booleanValue': True}
        }
    }


    response = create_firestore_document(SECRET_NAME, PROJECT_ID, COLLECTION_ID, DATABASE_NAME, DATA)
    return json.dumps(response, indent=4)