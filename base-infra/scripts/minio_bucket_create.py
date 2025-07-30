from minio import Minio
import sys

# args: bucket_name, host, port, access_key, secret_key
if len(sys.argv) != 6:
    print("Usage: python minio_bucket_create.py <bucket_name> <host> <port> <access_key> <secret_key>")
    sys.exit(1)

bucket, host, port, user, pwd = sys.argv[1:6]
client = Minio(f"{host}:{port}", access_key=user, secret_key=pwd, secure=False)

try:
    if not client.bucket_exists(bucket):
        client.make_bucket(bucket)
        print(f"Bucket '{bucket}' created successfully.")
    else:
        print(f"Bucket '{bucket}' already exists.")
except Exception as e:
    print(f"Error connecting to MinIO or creating bucket: {e}")
    sys.exit(1)
