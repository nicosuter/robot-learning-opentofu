# OpenCost Authentication for Public Endpoint

**Research Date**: 2026-03-16  
**Target Domain**: `cost.ethrc.rgn.dev`

---

## Executive Summary

OpenCost does **NOT** have built-in authentication for UI/API access. The `ADMIN_TOKEN` setting only protects write operations (cloud config endpoints), not general usage. To expose OpenCost publicly, authentication must be implemented at the ingress/proxy layer.

---

## Key Findings

### ❌ No Native Authentication
- Official API docs show no auth flow
- OpenAPI spec has no `securitySchemes` definitions
- Helm chart designed to run behind auth proxy
- Confirmed via GitHub issues (opencost/opencost-helm-chart#82, #84)

### ⚠️ Admin Token Limitations
The `opencost.exporter.adminToken` Helm value only protects:
- `POST /serviceKey` endpoints
- Cloud configuration endpoints

**Does NOT protect**: UI dashboard, API read endpoints, metrics

---

## Recommended Approaches

### Option 1: oauth2-proxy Sidecar (Recommended)

The OpenCost Helm chart has **native support** for oauth2-proxy as a sidecar container.

**Pros**:
- Native chart support (merged PR #84)
- Works with any OIDC provider (Auth0, Google, GitHub, Okta)
- Follows existing sidecar patterns
- Portable across cloud providers

**Cons**:
- Requires OIDC provider setup

**Example Configuration**:

```yaml
service:
  extraPorts:
    - name: oauth-proxy
      port: 8081
      targetPort: 8081

opencost:
  extraContainers:
    - name: oauth-proxy
      image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
      args:
        - --provider=oidc
        - --http-address=0.0.0.0:8081
        - --upstream=http://127.0.0.1:9090
        - --cookie-secure=true
        - --cookie-samesite=lax
      envFrom:
        - secretRef:
            name: opencost-oauth-secret
      ports:
        - name: oauth-proxy
          containerPort: 8081

  ui:
    ingress:
      enabled: true
      servicePort: oauth-proxy
      tls:
        - secretName: cost-ethrc-rgn-dev-tls
          hosts: [cost.ethrc.rgn.dev]
```

---

### Option 2: AWS ALB + Cognito

Extend existing ALB/WAF infrastructure with Cognito authentication.

**Pros**:
- Uses existing AWS infrastructure
- No additional containers
- Integrated with AWS ecosystem

**Cons**:
- AWS-specific (vendor lock-in)
- Requires Cognito user pool setup

**Example Ingress Annotation**:

```yaml
annotations:
  "kubernetes.io/ingress.class": "alb"
  "alb.ingress.kubernetes.io/scheme": "internet-facing"
  "alb.ingress.kubernetes.io/auth-type": "cognito"
  "alb.ingress.kubernetes.io/auth-idp-cognito": |
    {
      "UserPoolArn": "arn:aws:cognito-idp:...",
      "UserPoolClientId": "...",
      "UserPoolDomain": "..."
    }
```

---

### Option 3: WAF IP Whitelist (Minimal)

Simple IP-based restriction using existing WAF configuration.

**Pros**:
- Simplest implementation
- Uses existing WAF rules

**Cons**:
- IP-based only (not true user authentication)
- Hard to manage for dynamic IPs

---

## Implementation Plan

### Phase 1: Infrastructure Setup
- [ ] Add `opencost_hostname` variable to `variables.tf`
- [ ] Add `opencost_certificate_arn` variable to `variables.tf`
- [ ] Create ACM certificate for `cost.ethrc.rgn.dev` in `acm.tf`
- [ ] Create Route 53 record for `cost.ethrc.rgn.dev`

### Phase 2: Authentication Layer
- [ ] Choose OIDC provider (Auth0, Google, GitHub, etc.)
- [ ] Create OAuth application/credentials
- [ ] Store OAuth secrets in Kubernetes (create `opencost-oauth-secret`)

### Phase 3: OpenCost Configuration
- [ ] Update `modules/aws/eks-addons/opencost.tf`:
  - [ ] Add oauth2-proxy sidecar container
  - [ ] Add extra service port for oauth-proxy
  - [ ] Configure UI ingress with oauth-proxy backend
  - [ ] Add WAF annotations
  - [ ] Add TLS configuration

### Phase 4: Security Hardening
- [ ] Verify WAF rules apply to new endpoint
- [ ] Set `opencost.exporter.adminToken` for write protection
- [ ] Disable MCP server if not needed (`opencost.mcp.enabled: false`)
- [ ] Add rate limiting at ALB/WAF level
- [ ] Configure audit logging

### Phase 5: Testing
- [ ] Test authentication flow
- [ ] Verify unauthorized access is blocked
- [ ] Test with authorized user
- [ ] Verify cost data loads correctly

---

## Files to Modify

| File | Changes |
|------|---------|
| `variables.tf` | Add `opencost_hostname`, `opencost_certificate_arn` |
| `acm.tf` | Add ACM certificate and Route 53 record |
| `modules/aws/eks-addons/opencost.tf` | Add oauth2-proxy sidecar + ingress |
| `modules/aws/eks-addons/variables.tf` | Add opencost-related variables |
| `terraform.tfvars` | Add domain configuration |

---

## Security Considerations

### Cost Data Sensitivity
- Cost data reveals namespace/team spending patterns
- Cloud usage patterns can expose workload details
- Treat as internal analytics data unless properly secured

### Recommended Protections
1. **TLS everywhere** (ALB terminates TLS)
2. **WAF rules** (geo-blocking + IP restrictions already in place)
3. **Rate limiting** (prevent query abuse)
4. **Audit logging** (track access)
5. **Network policies** (restrict pod-to-pod traffic)
6. **Admin token** (protect write endpoints)

### MCP Server Warning
The MCP (Model Context Protocol) server is enabled by default in recent OpenCost versions. Consider disabling unless explicitly needed for AI agent integration:

```yaml
opencost:
  mcp:
    enabled: false
```

---

## References

- OpenCost API Docs: https://opencost.io/docs/integrations/api/
- OpenCost UI Installation: https://opencost.io/docs/installation/ui
- Helm Chart Values: https://github.com/opencost/opencost-helm-chart/blob/main/charts/opencost/values.yaml
- oauth2-proxy Sidecar PR: https://github.com/opencost/opencost-helm-chart/pull/84
- Auth Request Issue: https://github.com/opencost/opencost-helm-chart/issues/82

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-16 | oauth2-proxy recommended | Native chart support, flexible OIDC, portable |

---

## Appendix: Current OpenCost Configuration

Location: `modules/aws/eks-addons/opencost.tf`

Currently deployed:
- Prometheus (external mode)
- OpenCost UI enabled
- Internal ClusterIP service
- No ingress configured
- No authentication

---

*Last updated: 2026-03-16*
