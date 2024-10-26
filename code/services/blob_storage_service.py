import os
import io
from datetime import datetime, timedelta, timezone
from azure.identity import DefaultAzureCredential
from azure.storage.blob import (
    BlobServiceClient,
    generate_blob_sas,
    BlobSasPermissions,
    ContentSettings,
    D
)


class CatPicsStorageService:
    def __init__(self):
        self.container_name = os.getenv("AZURE_STORAGE_CONTAINER_NAME")
        self.account_name = os.getenv("AZURE_STORAGE_ACCOUNT_NAME")

        self.blob_service_client = BlobServiceClient(
            account_url=f"https://{self.account_name}.blob.core.windows.net",
            credential=DefaultAzureCredential()
        )

    def get_readonly_url(self, blob: str, path: str) -> str:
        user_delegation_key = self.blob_service_client.get_user_delegation_key(
            key_start_time=datetime.now(timezone.utc) - timedelta(hours=1),
            key_expiry_time=datetime.now(timezone.utc) + timedelta(hours=2)
        )

        sas_url = generate_blob_sas(
            account_name=self.blob_service_client.account_name,
            container_name=self.container_name,
            blob_name=f"{path}/{blob}",
            user_delegation_key=user_delegation_key,
            permission=BlobSasPermissions(read=True),
            expiry=datetime.now(timezone.utc) + timedelta(hours=1),
        )
        blob_client = self.blob_service_client.get_blob_client(
            self.container_name, f"{path}/{blob}"
        )

        if not blob_client.exists():
            return None
        else:
            return f"{blob_client.url}?{sas_url}"

    def upload_pic(
        self, path: str, blob: str, file: io.BytesIO, content_type: str
    ) -> bool:
        content_settings = ContentSettings(content_type=content_type)

        blob_client = self.blob_service_client.get_blob_client(
            container=self.container_name, blob=f"{path}/{blob}"
        )
        blob_client.upload_blob(
            data=file, overwrite=True, content_settings=content_settings
        )

        return blob_client.exists()
