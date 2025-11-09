{{- define "myapp.name" -}}
{{- default .Chart.Name .Values.nameOverride }}
{{- end -}}

{{- define "myapp.fullname" -}}
{{- printf "%s-%s" (include "myapp.name" .) .Release.Name }}
{{- end -}}
