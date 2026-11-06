#!/usr/bin/env bash
# Deploys the local S3 server and gives orders-db a key for it. The key is
# generated here and stored only in the cluster.
set -euo pipefail
cd "$(dirname "$0")"

kubectl create namespace object-store --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create namespace orders --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if ! kubectl -n orders get secret orders-db-backup-s3 >/dev/null 2>&1; then
  key=$(openssl rand -hex 10)
  secret=$(openssl rand -hex 20)
  kubectl -n object-store create secret generic seaweedfs-s3-config \
    --from-literal=s3.json="$(printf '{"identities":[{"name":"orders-db","credentials":[{"accessKey":"%s","secretKey":"%s"}],"actions":["Read","Write","List","Tagging"]}]}' "$key" "$secret")" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n orders create secret generic orders-db-backup-s3 \
    --from-literal=ACCESS_KEY_ID="$key" \
    --from-literal=ACCESS_SECRET_KEY="$secret"
fi

kubectl apply -f seaweedfs.yaml
kubectl -n object-store rollout status deployment/seaweedfs --timeout=3m
