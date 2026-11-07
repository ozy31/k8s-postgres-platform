{{- define "pg.labels" -}}
team: {{ .Values.team }}
app.kubernetes.io/part-of: {{ .Values.team }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}
