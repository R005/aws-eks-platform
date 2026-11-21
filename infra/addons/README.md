# addons

Cluster add-ons the platform depends on: the EBS CSI driver with a default `gp3` StorageClass, the AWS Load Balancer Controller, External Secrets Operator, metrics-server and ExternalDNS.

## Design

The cluster is found by name and the OIDC provider by the cluster's issuer URL, so this stack never reads the `eks` state. The `helm` and `kubernetes` providers fetch a short-lived token with `aws eks get-token` on every run; no token lands in state or a kubeconfig.

Every controller that calls AWS gets its own IRSA role, trusted only for its exact ServiceAccount ([ADR 0005](../../docs/adr/0005-irsa-for-pod-aws-access.md)). Chart and add-on versions are variables with pinned defaults, so every upgrade is a reviewed change.

- EBS CSI driver: EKS managed add-on with the AWS managed policy. The `gp3` StorageClass is the only default: encrypted, `WaitForFirstConsumer` so the volume lands in the pod's AZ, expandable.
- AWS Load Balancer Controller: Helm chart in `kube-system`. Its IAM policy is the upstream `iam_policy.json`, vendored in [`policies/`](policies/) per controller version. `region` and `vpcId` are set because pods cannot reach instance metadata.
- External Secrets Operator: Helm chart with CRDs ([ADR 0004](../../docs/adr/0004-external-secrets-operator.md)). The role can only read secrets named `<project>/<env>/*`; the module's built-in policy is not used because it also grants list access on everything. The secret store ships with the app chart, because `kubernetes_manifest` cannot plan a resource whose CRD does not exist yet.
- metrics-server: EKS managed add-on. It needs no IAM role.
- ExternalDNS: Helm chart, limited to `lab.<domain>` by `domainFilters` and by an IAM policy on that zone only ([ADR 0010](../../docs/adr/0010-dns-delegated-lab-subdomain.md)). `policy: sync` removes records whose Ingress is gone, but only those its TXT registry marks as owned, so `NS`, `SOA` and the ACM validation record are never touched.

The Load Balancer Controller installs a mutating webhook for Services, so the other releases that create Services wait for it.

The stack also creates the app's `tasks` namespace, because the CI role can only work inside it and cannot create namespaces. A Role there lets the `gitlab-ci-deployers` group manage `ExternalSecret` and `SecretStore` objects, which `AmazonEKSEditPolicy` does not cover.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # set owner and domain_name
cp backend.hcl.example backend.hcl             # replace <account-id>
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan                     # fails until eks is applied
terraform apply tfplan

kubectl get storageclass                       # gp3 (default)
kubectl -n kube-system get deploy aws-load-balancer-controller ebs-csi-controller metrics-server
kubectl -n external-secrets get pods
kubectl -n external-dns logs deploy/external-dns
```

Normally `make up` applies it last.

## Upgrades

```bash
aws eks describe-addon-versions --kubernetes-version 1.37 --addon-name aws-ebs-csi-driver \
  --query 'addons[0].addonVersions[0:3].addonVersion'
helm search repo eks/aws-load-balancer-controller --versions | head -3
```

For the Load Balancer Controller, first add `docs/install/iam_policy.json` from the matching controller tag as `policies/aws-load-balancer-controller-v<version>.json`, then bump `lbc_chart_version`. Without the file the plan fails.

## Cost and teardown

The stack adds no hourly cost. The cost comes from what the controllers create: an ALB per Ingress or LoadBalancer Service (about $16/month each) and a `gp3` volume per PVC (about $0.08 per GB-month).

Terraform does not own those load balancers and volumes, so delete the apps while the controllers are still running. `make down` enforces this: its `check-clean` step fails while a release, Ingress, LoadBalancer Service or PVC still exists. Override the target with `make down CLUSTER=<name> REGION=<region>`. A PersistentVolume with a `Retain` policy keeps its EBS volume after the PVC is gone, and the check cannot see it.
