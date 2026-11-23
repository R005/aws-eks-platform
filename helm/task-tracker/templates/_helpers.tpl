{{/* Without the chart version and image tag, so a release doesn't restart pods using it. */}}
{{- define "task-tracker.podLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "task-tracker.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "task-tracker.podLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
{{- end }}

{{/* Call with (dict "ctx" $ "component" "api"). Never change these: selectors are immutable. */}}
{{- define "task-tracker.selectorLabels" -}}
app.kubernetes.io/name: {{ .ctx.Chart.Name }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "task-tracker.apiImage" -}}
{{- $registry := required "image.registry is required (<account-id>.dkr.ecr.<region>.amazonaws.com)" .Values.image.registry -}}
{{- $tag := required "image.tag is required (the short Git SHA pushed by make image)" .Values.image.tag -}}
{{- printf "%s/%s:%s" $registry .Values.image.repository $tag -}}
{{- end }}

{{- define "task-tracker.postgresName" -}}{{ .Release.Name }}-postgres{{- end }}
{{- define "task-tracker.dbSecretName" -}}{{ .Release.Name }}-db{{- end }}

{{/* Shared by the api and the migrate Job. */}}
{{- define "task-tracker.dbEnv" -}}
- name: DB_HOST
  value: {{ include "task-tracker.postgresName" . }}
- name: DB_PORT
  value: {{ .Values.database.port | quote }}
- name: DB_NAME
  value: {{ .Values.database.name | quote }}
- name: DB_USER
  value: {{ .Values.database.user | quote }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "task-tracker.dbSecretName" . }}
      key: DB_PASSWORD
- name: LOG_LEVEL
  value: {{ .Values.api.logLevel | quote }}
{{- end }}

{{/* Matches the Compose x-hardening block. */}}
{{- define "task-tracker.apiPodSecurityContext" -}}
runAsNonRoot: true
runAsUser: 65532
runAsGroup: 65532
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{- define "task-tracker.apiContainerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end }}
