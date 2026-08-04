#!/usr/bin/env python3
"""Mirror a public S3 prefix of organism images into a local directory.

Stdlib only: the deploy hosts have no boto3, and the bucket allows anonymous
reads, so there is nothing to authenticate against. Objects already present at
the same size are skipped, which makes a no-op run cost one listing request
rather than re-pulling several hundred MB on every deploy.
"""

import argparse
import os
import shutil
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

S3_NS = {"s3": "http://s3.amazonaws.com/doc/2006-03-01/"}
RETRIES = 3


def list_objects(endpoint, bucket, prefix):
    """Yield (key, size) for every object under prefix, following pagination."""
    token = None
    while True:
        params = {"list-type": "2", "prefix": prefix, "max-keys": "1000"}
        if token:
            params["continuation-token"] = token
        url = "{}/{}?{}".format(endpoint, bucket, urllib.parse.urlencode(params))
        with urllib.request.urlopen(url, timeout=60) as response:
            root = ET.fromstring(response.read())

        for contents in root.findall("s3:Contents", S3_NS):
            key = contents.find("s3:Key", S3_NS).text
            if key.endswith("/"):
                continue
            yield key, int(contents.find("s3:Size", S3_NS).text)

        truncated = root.find("s3:IsTruncated", S3_NS)
        next_token = root.find("s3:NextContinuationToken", S3_NS)
        if truncated is None or truncated.text != "true" or next_token is None:
            return
        token = next_token.text


def download(url, dest):
    """Fetch url to dest via a temp file, so an interrupted run never leaves a
    truncated image that the size check would later accept as complete."""
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(dest), prefix=".sync-")
    try:
        with os.fdopen(tmp_fd, "wb") as out:
            with urllib.request.urlopen(url, timeout=120) as response:
                shutil.copyfileobj(response, out, 1 << 20)
        os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, dest)
    except BaseException:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", required=True, help="S3-compatible endpoint URL")
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--prefix", required=True, help="key prefix, e.g. images/")
    parser.add_argument("--dest", required=True, help="local directory to mirror into")
    args = parser.parse_args()

    endpoint = args.endpoint.rstrip("/")
    dest_root = os.path.abspath(args.dest)
    os.makedirs(dest_root, exist_ok=True)

    downloaded = skipped = failed = 0
    downloaded_bytes = 0

    for key, size in list_objects(endpoint, args.bucket, args.prefix):
        relative = key[len(args.prefix) :] if key.startswith(args.prefix) else key
        local_path = os.path.abspath(os.path.join(dest_root, relative))
        if os.path.commonpath([dest_root, local_path]) != dest_root:
            print("refusing key outside destination: {}".format(key), file=sys.stderr)
            failed += 1
            continue

        if os.path.isfile(local_path) and os.path.getsize(local_path) == size:
            skipped += 1
            continue

        os.makedirs(os.path.dirname(local_path), exist_ok=True)
        url = "{}/{}/{}".format(endpoint, args.bucket, urllib.parse.quote(key))
        for attempt in range(1, RETRIES + 1):
            try:
                download(url, local_path)
                downloaded += 1
                downloaded_bytes += size
                break
            except (urllib.error.URLError, OSError) as exc:
                if attempt == RETRIES:
                    print(
                        "failed after {} attempts: {} ({})".format(RETRIES, key, exc),
                        file=sys.stderr,
                    )
                    failed += 1

    print(
        "downloaded={} skipped={} failed={} bytes={}".format(
            downloaded, skipped, failed, downloaded_bytes
        )
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
