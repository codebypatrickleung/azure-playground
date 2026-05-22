{{/*
Expand the name of the chart.
*/}}
{{- define "azure-playground.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "azure-playground.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Frontend labels
*/}}
{{- define "azure-playground.frontend.labels" -}}
{{ include "azure-playground.labels" . }}
app.kubernetes.io/name: {{ include "azure-playground.name" . }}-frontend
{{- end }}

{{/*
Frontend selector labels
*/}}
{{- define "azure-playground.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "azure-playground.name" . }}-frontend
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
LLM service labels
*/}}
{{- define "azure-playground.llmService.labels" -}}
{{ include "azure-playground.labels" . }}
app.kubernetes.io/name: {{ include "azure-playground.name" . }}-llm-service
{{- end }}

{{/*
LLM service selector labels
*/}}
{{- define "azure-playground.llmService.selectorLabels" -}}
app.kubernetes.io/name: {{ include "azure-playground.name" . }}-llm-service
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
