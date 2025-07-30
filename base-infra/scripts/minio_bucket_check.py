#!/usr/bin/env python3
import sys, json
from minio import Minio

def main():
    # args: bucket_name, host, port, access_key, secret_key
    if len(sys.argv) != 6:
        print(json.dumps({"exists":"false"}))
        sys.exit(1)
    bucket, host, port, access_key, secret_key = sys.argv[1:]
    endpoint = f"{host}:{port}"
    client = Minio(endpoint,
                   access_key=access_key,
                   secret_key=secret_key,
                   secure=False)
    try:
        exists = client.bucket_exists(bucket)
    except Exception:
        exists = False
    print(json.dumps({"exists":"true" if exists else "false"}))

if __name__=="__main__":
    main()
