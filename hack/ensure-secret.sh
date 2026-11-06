#!/usr/bin/env bash
# Creates a basic-auth Secret with a random password if it does not exist.
# Passwords never live in git; in a real environment they come from Key
# Vault or Secrets Manager through External Secrets.
#
# usage: hack/ensure-secret.sh <namespace> <secret-name> <username>
set -euo pipefail
ns=$1 name=$2 user=$3

kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns"
if kubectl -n "$ns" get secret "$name" >/dev/null 2>&1; then
  exit 0
fi
kubectl -n "$ns" create secret generic "$name" \
  --type=kubernetes.io/basic-auth \
  --from-literal=username="$user" \
  --from-literal=password="$(openssl rand -base64 24 | tr -d '/+=')"
# Lets the operator pick up a rotated password without a restart.
kubectl -n "$ns" label secret "$name" cnpg.io/reload=true
