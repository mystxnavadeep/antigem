#!/usr/bin/env python3
"""
antiGem Cloud Workspace - Google Drive API Helper
Handles secure, authenticated file operations on Google Drive using GDRIVE_CREDENTIALS_JSON.
Never logs or prints secrets.
"""

import os
import sys
import json
import io
import argparse
from typing import Optional, Dict, Any, List

try:
    from google.oauth2 import service_account
    from google.oauth2.credentials import Credentials as UserCredentials
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload, MediaIoBaseDownload
    GOOGLE_LIBS_AVAILABLE = True
except ImportError:
    GOOGLE_LIBS_AVAILABLE = False


BACKUP_FOLDER_DEFAULT = "AntiGem-Cloud-Backups"
SCOPES = ['https://www.googleapis.com/auth/drive']


def get_service():
    """Builds and returns Google Drive API service using GDRIVE_CREDENTIALS_JSON."""
    if not GOOGLE_LIBS_AVAILABLE:
        print("❌ Error: google-api-python-client and google-auth are required.", file=sys.stderr)
        print("Install via: pip install google-api-python-client google-auth", file=sys.stderr)
        sys.exit(1)

    creds_raw = os.getenv("GDRIVE_CREDENTIALS_JSON", "").strip()
    if not creds_raw:
        print("❌ Error: GDRIVE_CREDENTIALS_JSON environment variable is not set.", file=sys.stderr)
        sys.exit(1)

    try:
        creds_data = json.loads(creds_raw)
    except json.JSONDecodeError as e:
        print(f"❌ Error: Invalid JSON in GDRIVE_CREDENTIALS_JSON: {e}", file=sys.stderr)
        sys.exit(1)

    creds = None
    if creds_data.get("type") == "service_account":
        creds = service_account.Credentials.from_service_account_info(
            creds_data, scopes=SCOPES
        )
    elif "refresh_token" in creds_data:
        creds = UserCredentials.from_authorized_user_info(
            creds_data, scopes=SCOPES
        )
    else:
        # Generic service account structure
        try:
            creds = service_account.Credentials.from_service_account_info(
                creds_data, scopes=SCOPES
            )
        except Exception as e:
            print(f"❌ Error: Could not determine credentials type: {e}", file=sys.stderr)
            sys.exit(1)

    return build('drive', 'v3', credentials=creds, cache_discovery=False)


def get_or_create_folder(service, folder_name: str = BACKUP_FOLDER_DEFAULT) -> str:
    """Finds or creates the designated backup folder, or uses GDRIVE_FOLDER_ID if set."""
    custom_folder_id = os.getenv("GDRIVE_FOLDER_ID", "").strip()
    if custom_folder_id:
        return custom_folder_id

    # Check if folder exists
    query = f"name = '{folder_name}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
    response = service.files().list(
        q=query, spaces='drive', fields='files(id, name)', pageSize=10
    ).execute()
    files = response.get('files', [])

    if files:
        return files[0]['id']

    # Create folder
    file_metadata = {
        'name': folder_name,
        'mimeType': 'application/vnd.google-apps.folder'
    }
    folder = service.files().create(body=file_metadata, fields='id').execute()
    return folder.get('id')


def upload_file(local_path: str, remote_name: Optional[str] = None) -> bool:
    """Uploads local_path to Google Drive backup folder."""
    if not os.path.isfile(local_path):
        print(f"❌ Error: Local file '{local_path}' does not exist.", file=sys.stderr)
        return False

    service = get_service()
    folder_id = get_or_create_folder(service)
    file_name = remote_name if remote_name else os.path.basename(local_path)

    file_metadata = {
        'name': file_name,
        'parents': [folder_id]
    }
    media = MediaFileUpload(local_path, mimetype='application/octet-stream', resumable=True)

    print(f"  • Uploading '{file_name}' to Google Drive...")
    file = service.files().create(
        body=file_metadata,
        media_body=media,
        fields='id, name, size, md5Checksum'
    ).execute()

    file_id = file.get('id')
    print(f"  ✅ Upload complete! Drive File ID: {file_id}")
    return True


def list_backups() -> List[Dict[str, Any]]:
    """Lists files in the backup folder ordered by creation date."""
    service = get_service()
    folder_id = get_or_create_folder(service)

    query = f"'{folder_id}' in parents and trashed = false"
    response = service.files().list(
        q=query,
        spaces='drive',
        fields='files(id, name, size, createdTime, modifiedTime, md5Checksum)',
        orderBy='modifiedTime desc',
        pageSize=50
    ).execute()

    return response.get('files', [])


def download_latest(output_path: str, pattern: str = "antigem_") -> bool:
    """Finds and downloads the latest backup file matching pattern."""
    service = get_service()
    backups = list_backups()

    matched = [f for f in backups if pattern in f.get('name', '') and f.get('name', '').endswith('.enc')]
    if not matched:
        print(f"ℹ No previous backups matching '{pattern}' found in Google Drive.", file=sys.stderr)
        return False

    latest = matched[0]
    file_id = latest['id']
    file_name = latest['name']
    file_size = latest.get('size', 'unknown')

    print(f"  • Found latest backup: {file_name} ({file_size} bytes)")
    return download_by_id(service, file_id, output_path)


def download_by_id(service, file_id: str, output_path: str) -> bool:
    """Downloads a file by ID to output_path."""
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    request = service.files().get_media(fileId=file_id)

    with open(output_path, 'wb') as fh:
        downloader = MediaIoBaseDownload(fh, request, chunksize=1024*1024*4)
        done = False
        print(f"  • Downloading backup archive...")
        while not done:
            status, done = downloader.next_chunk()
            if status:
                print(f"    Progress: {int(status.progress() * 100)}%", end='\r', flush=True)
        print()

    print(f"  ✅ Download complete: {output_path}")
    return True


def cleanup_old(keep: int = 15):
    """Prunes backups beyond the keep threshold."""
    service = get_service()
    backups = list_backups()
    if len(backups) <= keep:
        return

    to_delete = backups[keep:]
    print(f"  • Pruning {len(to_delete)} old backup(s)...")
    for f in to_delete:
        try:
            service.files().delete(fileId=f['id']).execute()
            print(f"    Deleted old snapshot: {f.get('name')}")
        except Exception as e:
            print(f"    Warning: Failed to delete {f.get('name')}: {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Google Drive Helper for antiGem Cloud")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Upload
    upload_parser = subparsers.add_parser("upload")
    upload_parser.add_argument("file", help="Path to local file to upload")
    upload_parser.add_argument("--name", help="Remote file name", default=None)

    # Download Latest
    dl_parser = subparsers.add_parser("download-latest")
    dl_parser.add_argument("output", help="Path to save downloaded file")
    dl_parser.add_argument("--pattern", help="Filename match pattern", default="antigem_")

    # List
    subparsers.add_parser("list")

    # Cleanup
    clean_parser = subparsers.add_parser("cleanup")
    clean_parser.add_argument("--keep", type=int, default=15)

    args = parser.parse_args()

    if args.command == "upload":
        success = upload_file(args.file, args.name)
        sys.exit(0 if success else 1)
    elif args.command == "download-latest":
        success = download_latest(args.output, args.pattern)
        sys.exit(0 if success else 1)
    elif args.command == "list":
        files = list_backups()
        print(json.dumps(files, indent=2))
    elif args.command == "cleanup":
        cleanup_old(args.keep)


if __name__ == "__main__":
    main()
