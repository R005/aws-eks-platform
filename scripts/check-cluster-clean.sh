#!/usr/bin/env bash
# Fails while the cluster still has objects that make controllers create AWS resources outside Terraform:
#   - Ingresses and LoadBalancer Services -> ALBs/NLBs, target groups, security groups (AWS Load Balancer Controller)
#   - PersistentVolumeClaims              -> EBS volumes (EBS CSI driver)
#   - the app Helm releases given as <namespace>/<release> arguments, which own such objects
# Destroying the addons stack removes those controllers, so anything still listed here would be orphaned
# in AWS (and still billed), and could block the VPC destroy in the network stack.
#
# Usage: scripts/check-cluster-clean.sh <cluster-name> <region> [<namespace>/<release> ...]
set -euo pipefail

cluster="${1:?usage: $0 <cluster-name> <region> [<namespace>/<release> ...]}"
region="${2:?usage: $0 <cluster-name> <region> [<namespace>/<release> ...]}"
shift 2

# Temporary kubeconfig: always targets this cluster and leaves the user's kubeconfig untouched.
# It holds no token, only an exec entry that runs `aws eks get-token`.
kubeconfig="$(mktemp)"
trap 'rm -f "$kubeconfig"' EXIT
aws eks update-kubeconfig --name "$cluster" --region "$region" --kubeconfig "$kubeconfig" >/dev/null

k() { kubectl --kubeconfig "$kubeconfig" "$@"; }

ingresses="$(k get ingress --all-namespaces --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name)"
lb_services="$(k get service --all-namespaces -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')"
pvcs="$(k get pvc --all-namespaces --no-headers -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name)"

# Helm stores each release as Secrets labelled owner=helm,name=<release> in the release namespace.
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
