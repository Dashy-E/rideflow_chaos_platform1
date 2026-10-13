{{/*
Common labels applied to every resource in this chart.
*/}}
{{- define "rideflow.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: rideflow
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Selector labels for a given service name (used by Deployment/Service/HPA/PDB
selectors — must be stable across chart versions).
*/}}
{{- define "rideflow.selectorLabels" -}}
app: {{ .serviceName }}
app.kubernetes.io/name: {{ .serviceName }}
app.kubernetes.io/instance: {{ .releaseName }}
{{- end -}}

{{/*
Full image reference for an application service: <registry>/<image>:<tag>
*/}}
{{- define "rideflow.image" -}}
{{- $global := .global -}}
{{- $svc := .svc -}}
{{- printf "%s/%s:%s" $global.imageRegistry $svc.image (default $global.imageTag $svc.imageTag) -}}
{{- end -}}
