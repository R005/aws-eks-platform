# task-tracker chart

Deploys the `api` service with its PostgreSQL database into the `tasks` namespace: the database password from AWS Secrets Manager, a single-replica Postgres StatefulSet, an Alembic migration Job, the api Deployment and an internet-facing ALB Ingress at `tasks.lab.<domain>`. Installed with `make deploy` from the repository root.

## Objects

| Template | Object | Purpose |
| --- | --- | --- |
| `secretstore.yaml` | `SecretStore` `aws-secrets-manager` | Points External Secrets at Secrets Manager in the cluster's region. No `auth` block, so the controller uses its own IRSA role |
| `externalsecret.yaml` | `ExternalSecret` `<release>-db` | Copies the `password` field of `eks-platform/dev/db` into the Secret `<release>-db`, key `DB_PASSWORD`, refreshed hourly |
| `postgres-statefulset.yaml` | `StatefulSet` `<release>-postgres` | PostgreSQL 18, same digest-pinned image as Compose, 10 Gi `gp3` volume, `pg_isready` readiness probe |
| `postgres-service.yaml` | headless `Service` `<release>-postgres` | Stable DNS name for the database pod (`DB_HOST`) |
| `migrate-job.yaml` | `Job` `<release>-migrate` (hook) | `alembic upgrade head` from the api image, `post-install` and `pre-upgrade` |
| `api-deployment.yaml` | `Deployment` `<release>-api` | 2 replicas, startup/liveness/readiness probes, hardened security context |
| `api-service.yaml` | `Service` `<release>-api` | ClusterIP on port 8000 |
| `ingress.yaml` | `Ingress` `<release>-api` | Internet-facing ALB for `ingress.host`: HTTP 80 redirects to HTTPS 443, IP targets, health check on `/readyz` |

## Design

- **Secrets.** The password exists only in Secrets Manager and in the synced Kubernetes Secret. It is never in values, Git or the Helm release. The `ExternalSecret` owns the Secret (`creationPolicy: Owner`), so uninstalling removes it. The store is namespaced (`SecretStore`), so the chart is self-contained. The controller's IRSA role allows reads only on `eks-platform/dev/*`.
- **Migration timing.** Helm runs `pre-install` hooks before it creates any release object. On the first install, the database and its Secret would not exist yet. The Job therefore runs `post-install` (after the release objects are created and, with `--wait`, ready) and `pre-upgrade` (before new api pods roll out). On the first install only, the api is serving for a few seconds before the `tasks` table exists. A failed Job is kept for its logs and replaced on the next run.
- **Probes** follow [`apps/api/OPERATIONS.md`](../../apps/api/OPERATIONS.md). The startup probe on `/healthz` allows 30 s. The liveness probe on `/healthz` has no dependencies, so a database outage never restarts the api. The readiness probe on `/readyz` checks the database and only takes the replica out of the Service.
- **Shutdown.** A 15 s `preStop` sleep (native `sleep` action, since the distroless image has no shell) keeps the pod serving while it is removed from Service endpoints and deregistered from the ALB target group, which takes longer than the endpoint update. Only then does the api get SIGTERM and drain for up to 20 s. The grace period is derived from the sleep (`preStopSleepSeconds` + 25, so 40 s), because the sleep counts against it.
- **Resources.** The api requests 100m CPU and 128Mi, with a 256Mi memory limit and no CPU limit, because one replica can use more than one core under load. Postgres requests 100m and 256Mi, with a 512Mi limit.
- **Hardening.** The api and migrate containers match the Compose `x-hardening` block: UID 65532, read-only root filesystem, all capabilities dropped, no privilege escalation, `RuntimeDefault` seccomp profile, a disk-backed `emptyDir` on `/tmp`, and no ServiceAccount token. Postgres runs as the image's `postgres` user (UID 999, `fsGroup` 999) with all capabilities dropped. Its root filesystem stays writable, because the entrypoint writes outside the data volume.
- **Image.** `image.registry` and `image.tag` are required and have no default, so nothing account-specific is committed. Tags are immutable in ECR, so `pullPolicy: IfNotPresent` is safe.
- **Ingress** ([ADR 0014](../../docs/adr/0014-ingress-via-aws-load-balancer-controller.md)). `ingressClassName: alb` hands it to the AWS Load Balancer Controller, which creates an internet-facing ALB in the public subnets.
  - **Targets.** `target-type: ip` registers pod IPs in the target group, so traffic goes straight to the pods without a NodePort hop. The health check uses `/readyz`, the same signal as the readiness probe, so a replica that loses the database leaves the ALB as well as the Service.
  - **TLS.** Listeners on 80 and 443, and `ssl-redirect: '443'` answers plain HTTP with a 301 to HTTPS. No `certificate-arn` is set: the controller discovers the ACM certificate whose names match the rule host (`*.lab.<domain>` from the `foundation` stack). This works because the HTTPS listener is declared in `listen-ports`.
  - **DNS.** ExternalDNS (`addons` stack) reads the rule host and creates the alias record to the ALB in `lab.<domain>`.
  - **Host.** `ingress.host` is required and has no default, so the domain is never committed. `make deploy` builds it as `tasks.` plus the `foundation` output `lab_zone_name`.
- **Rollouts.** `maxUnavailable: 0`, `maxSurge: 1`: capacity never drops below two replicas.

The single Postgres replica, without backups, is a lab shortcut ([ADR 0002](../../docs/adr/0002-postgres-statefulset-first-rds-later.md)). RDS replaces it at M11.

## Values

| Key | Default | Description |
| --- | --- | --- |
| `image.registry` | `""` (required) | `<account-id>.dkr.ecr.<region>.amazonaws.com` |
| `image.repository` | `eks-platform/api` | ECR repository |
| `image.tag` | `""` (required) | Short Git SHA pushed by `make image` |
| `api.replicas` | `2` | api replicas |
| `api.resources` | see `values.yaml` | Requests and limits for the api and migrate containers |
| `database.name`, `database.user` | `tasks` | Database name and user |
| `postgres.image` | `postgres:18.6-trixie@sha256:…` | Same as `docker-compose.yml` |
| `postgres.storage.size` | `10Gi` | Volume size |
| `postgres.storage.storageClassName` | `gp3` | StorageClass from the `addons` stack |
| `externalSecrets.region` | `""` (required) | Region of the Secrets Manager secret |
| `externalSecrets.secretName` | `eks-platform/dev/db` | Secret created by the `foundation` stack |
| `ingress.enabled` | `true` | Render the Ingress |
| `ingress.className` | `alb` | IngressClass of the AWS Load Balancer Controller |
| `ingress.host` | `""` (required) | Public host, `tasks.lab.<domain>` |
| `ingress.healthCheckPath` | `/readyz` | ALB target health check path |

## Validate

```bash
helm lint helm/task-tracker --set image.registry=<registry> --set image.tag=<tag> \
  --set externalSecrets.region=<region> --set ingress.host=tasks.lab.<domain>
helm template task-tracker helm/task-tracker -n tasks --set image.registry=<registry> --set image.tag=<tag> \
  --set externalSecrets.region=<region> --set ingress.host=tasks.lab.<domain>
```

Without the four required values, rendering fails with a message naming the missing value.

## Removal

`make undeploy` uninstalls the release and then deletes the Postgres PVC. Deleting the Ingress makes the controller delete the ALB and its target groups, and ExternalDNS removes the DNS record on its next sync. StatefulSet volume claims are not removed by `helm uninstall`, and the EBS volume behind them is only deleted with the claim. Deleting the PVC deletes the database.
