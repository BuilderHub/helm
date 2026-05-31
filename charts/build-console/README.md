# BuilderHub Console Helm Chart

This Helm chart deploys the BuilderHub Console application to a Kubernetes cluster. The console provides builder and organization management capabilities.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+

## Installing the Chart

To install the chart with the release name `build-console`:

```bash
helm install build-console ./charts/build-console
```

To install with custom values:

```bash
helm install build-console ./charts/build-console -f custom-values.yaml
```

## Uninstalling the Chart

To uninstall the `build-console` deployment:

```bash
helm uninstall build-console
```

## Configuration

The following table lists the configurable parameters of the chart and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `2` |
| `image.repository` | Image repository | `ghcr.io/builderhub/build-console` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `image.tag` | Image tag | `""` (uses Chart.AppVersion) |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `80` |
| `service.targetPort` | Container target port | `3001` |
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.hosts` | Ingress hosts | `[console.example.com]` |
| `resources.limits.cpu` | CPU limit | `500m` |
| `resources.limits.memory` | Memory limit | `512Mi` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `256Mi` |
| `autoscaling.enabled` | Enable HPA | `false` |
| `autoscaling.minReplicas` | Minimum replicas | `2` |
| `autoscaling.maxReplicas` | Maximum replicas | `10` |
| `env` | Environment variables | See `values.yaml` |

## Examples

### Enable Ingress with TLS

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: console.builderhub.io
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: build-console-tls
      hosts:
        - console.builderhub.io
```

### Enable Autoscaling

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

### Custom Environment Variables

```yaml
env:
  - name: NODE_ENV
    value: "production"
  - name: CUSTOM_VAR
    value: "custom-value"

envFrom:
  - configMapRef:
      name: build-console-config
  - secretRef:
      name: build-console-secrets
```

### Use LoadBalancer Service

```yaml
service:
  type: LoadBalancer
  port: 80
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
```

## Production images

Client-side API calls use `NEXT_PUBLIC_API_URL`, which Next.js bakes into the JS bundle at **image build time** (not at pod startup). Production CI builds the image with:

```bash
docker build --build-arg NEXT_PUBLIC_API_URL=https://api.builder-hub.dev .
```

Runtime `env` values for `NEXT_PUBLIC_API_URL` only affect server-side rendering, not the browser bundle.

## Upgrading

To upgrade the chart:

```bash
helm upgrade build-console ./charts/build-console
```

## Testing

To test the chart rendering:

```bash
helm template build-console ./charts/build-console
```

To test with custom values:

```bash
helm template build-console ./charts/build-console -f test-values.yaml
```

To lint the chart:

```bash
helm lint ./charts/build-console
```
