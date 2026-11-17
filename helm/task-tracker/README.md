# task-tracker chart

Deploys the api and its PostgreSQL database into the `tasks` namespace, behind an internet-facing ALB at `tasks.lab.<domain>`. Installed with `make deploy` from the repository root.

## Design

The database password lives only in Secrets Manager and in the Secret that the `ExternalSecret` creates from it, never in values or the release. The namespaced `SecretStore` has no `auth` block, so External Secrets uses its own IRSA role, which may only read `eks-platform/dev/*`.

Postgres is a single-replica StatefulSet on a 10 Gi `gp3` volume ([ADR 0002](../../docs/adr/0002-postgres-statefulset-first-rds-later.md)). It has no backups; that is a lab shortcut until RDS at M11.

The migrate Job runs `post-install`, because on the first install the database and its Secret do not exist before the release objects, and `pre-upgrade` after that. As a result, on the very first install the api serves for a few seconds before the `tasks` table exists. A failed Job is kept for its logs.

The api's liveness probe has no dependencies; readiness and the ALB health check both use `/readyz`, so a replica that loses the database leaves the Service and the target group without restarting. A 15 s `preStop` sleep keeps the pod serving while the ALB deregisters it, which takes longer than the endpoint update. The grace period is derived from it (`preStopSleepSeconds + 25`). Rollouts use `maxUnavailable: 0`.

The api has no CPU limit, because one replica can use more than a core. Containers run with the same hardening as Compose: non-root, read-only root filesystem, no capabilities, `RuntimeDefault` seccomp.

The Ingress uses IP targets and listens on 80 and 443 with a redirect to HTTPS. No certificate ARN is set: the controller finds the ACM certificate that matches the host ([ADR 0014](../../docs/adr/0014-ingress-via-aws-load-balancer-controller.md)), and ExternalDNS creates the record.

## Values

`image.registry`, `image.tag`, `externalSecrets.region` and `ingress.host` are required and have no defaults, so nothing account-specific is committed. `make deploy` sets all four. Rendering fails with a clear message if one is missing.

`debugEndpoints.enabled` (default `false`) sets `ENABLE_DEBUG_ENDPOINTS=true` on the api container only. See [`values.yaml`](values.yaml) for the rest.

```bash
helm lint helm/task-tracker --set image.registry=<registry> --set image.tag=<tag> \
  --set externalSecrets.region=<region> --set ingress.host=tasks.lab.<domain>
```

## Removal

`make undeploy` uninstalls the release and deletes the Postgres PVC, which deletes the data. `helm uninstall` alone leaves the PVC and its EBS volume behind. The controller deletes the ALB with the Ingress, and ExternalDNS removes the record on its next sync.
