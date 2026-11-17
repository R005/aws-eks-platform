#!/usr/bin/env bash
# Fails while Ingresses, LoadBalancer Services, PVCs or the given Helm releases still exist. Their
# controllers create ALBs and EBS volumes outside Terraform; destroying addons first would orphan
# them (still billed) and block the VPC destroy.
# Usage: scripts/check-cluster-clean.sh <cluster-name> <region> [<namespace>/<release> ...]
set -euo pipefail

cluster="${1:?usage: $0 <cluster-name> <region> [<namespace>/<release> ...]}"
region="${2:?usage: $0 <cluster-name> <region> [<namespace>/<release> ...]}"
shift 2

# Temporary kubeconfig, so the check always targets this cluster and the user's file is untouched.
kubeconfig="$(mktemp)"
trap 'rm -f "$kubeconfig"' EXIT
aws eks update-kubeconfig --name "$cluster" --region "$region" --kubeconfig "$kubeconfig" >/dev/null

k() { kubectl --kubeconfig "$kubeconfig" "$@"; }

ingresses="$(k get ingress --all-namespaces --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name)"
lb_services="$(k get service --all-namespaces -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')"
pvcs="$(k get pvc --all-namespaces --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name)"

# Helm stores releases as Secrets labelled owner=helm,name=<release>.
releases=""
for ref in "$@"; do
  if [[ -n "$(k get secret --namespace "${ref%%/*}" --selector "owner=helm,name=${ref#*/}" -o name)" ]]; then
    releases+="${ref}"$'\n'
  fi
done

failed=0
report() {
  if [[ -n "$2" ]]; then
    echo "Still present: $1" >&2
    sed 's/^/  /' <<<"$2" >&2
    failed=1
  fi
}
report "Helm release" "${releases%$'\n'}"
report "Ingress" "$ingresses"
report "Service type LoadBalancer" "$lb_services"
report "PersistentVolumeClaim" "$pvcs"

if [[ "$failed" -ne 0 ]]; then
  echo "Delete these first (make undeploy), wait for the controllers to remove the AWS resources, then retry." >&2
  exit 1
fi
echo "No app releases, Ingresses, LoadBalancer Services or PVCs in $cluster."
