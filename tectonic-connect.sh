kubectl get pods -l app=tectonic-console --namespace="monitoring" \
  -o template --template="{{range.items}}{{.metadata.name}}{{end}}" \
  | xargs -I{} kubectl  --kubeconfig="kubeconfig" --namespace="monitoring" port-forward {} 9000
