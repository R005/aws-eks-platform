#!/usr/bin/env bash
# Fails while the cluster still has objects that make controllers create AWS resources outside Terraform:
#   - Ingresses and LoadBalancer Services -> ALBs/NLBs, target groups, security groups (AWS Load Balancer Controller)
#   - PersistentVolumeClaims              -> EBS volumes (EBS CSI driver)
# Destroying the addons stack removes those controllers, so anything still listed here would be orphaned
# in AWS (and still billed), and could block the VPC destroy in the network stack.
#
# Usage: scripts/check-cluster-clean.sh <cluster-name> <region>
set -euo pipefail

cluster="${1:?usage: $0 <cluster-name> <region>}"
region="${2:?usage: $0 <cluster-name> <region>}"

# Temporary kubeconfig: always targets this cluster and leaves the user's kubeconfig untouched.
# It holds no token, only an exec entry that runs `aws eks get-token`.
kubeconfig="$(mktemp)"
trap 'rm -f "$kubeconfig"' EXIT
aws eks update-kubeconfig --name "$cluster" --region "$region" --kubeconfig "$kubeconfig" >/dev/null

k() { kubectl --kubeconfig "$kubeconfig" "$@"; }

ingresses="$(k get ingress --all-namespaces --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name)"
lb_services="$(k get service --all-namespaces -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')"
pvcs="$(k get pvc --all-namespaces --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name)"

failed=0
report() {
  if [[ -n "$2" ]]; then
    echo "Still present: $1" >&2
    sed 's/^/  /' <<<"$2" >&2
    failed=1
  fi
}
report "Ingress" "$ingresses"
report "Service type LoadBalancer" "$lb_services"
report "PersistentVolumeClaim" "$pvcs"

if [[ "$failed" -ne 0 ]]; then
  echo "Delete these first (helm uninstall the apps), wait for the controllers to remove the AWS resources, then retry." >&2
  exit 1
fi
echo "No Ingresses, LoadBalancer Services or PVCs in $cluster."
