# task-tracker chart

Deploys the `api` service with its PostgreSQL database into the `tasks` namespace: the database password from AWS Secrets Manager, a single-replica Postgres StatefulSet, an Alembic migration Job and the api Deployment. Installed with `make deploy` from the repository root.

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

## Design

- **Secrets.** The password exists only in Secrets Manager and in the synced Kubernetes Secret. It is never in values, Git or the Helm release. The `ExternalSecret` owns the Secret (`creationPolicy: Owner`), so uninstalling removes it. The store is namespaced (`SecretStore`), so the chart is self-contained. The controller's IRSA role allows reads only on `eks-platform/dev/*`.
- **Migration timing.** Helm runs `pre-install` hooks before it creates any release object. On the first install, the database and its Secret would not exist yet. The Job therefore runs `post-install` (after the release objects are created and, with `--wait`, ready) and `pre-upgrade` (before new api pods roll out). On the first install only, the api is serving for a few seconds before the `tasks` table exists. A failed Job is kept for its logs and replaced on the next run.
- **Probes** follow [`apps/api/OPERATIONS.md`](../../apps/api/OPERATIONS.md). The startup probe on `/healthz` allows 30 s. The liveness probe on `/healthz` has no dependencies, so a database outage never restarts the api. The readiness probe on `/readyz` checks the database and only takes the replica out of the Service.
- **Shutdown.** A 5 s `preStop` sleep (native `sleep` action, since the distroless image has no shell) keeps the pod serving while it is removed from endpoints. The api then drains for up to 20 s, inside the 30 s grace period.
- **Resources.** The api requests 100m CPU and 128Mi, with a 256Mi memory limit and no CPU limit, because one replica can use more than one core under load. Postgres requests 100m and 256Mi, with a 512Mi limit.
- **Hardening.** The api and migrate containers match the Compose `x-hardening` block: UID 65532, read-only root filesystem, all capabilities dropped, no privilege escalation, `RuntimeDefault` seccomp profile, a disk-backed `emptyDir` on `/tmp`, and no ServiceAccount token. Postgres runs as the image's `postgres` user (UID 999, `fsGroup` 999) with all capabilities dropped. Its root filesystem stays writable, because the entrypoint writes outside the data volume.
- **Image.** `image.registry` and `image.tag` are required and have no default, so nothing account-specific is committed. Tags are immutable in ECR, so `pullPolicy: IfNotPresent` is safe.
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

## Validate

```bash
helm lint helm/task-tracker --set image.registry=<registry> --set image.tag=<tag> --set externalSecrets.region=<region>
helm template task-tracker helm/task-tracker -n tasks \
  --set image.registry=<registry> --set image.tag=<tag> --set externalSecrets.region=<region>
```

Without the three required values, rendering fails with a message naming the missing value.

## Removal

`make undeploy` uninstalls the release and then deletes the Postgres PVC. StatefulSet volume claims are not removed by `helm uninstall`, and the EBS volume behind them is only deleted with the claim. Deleting the PVC deletes the database.
