# BYOIP IPv6 Setup Guide

This guide walks through setting up Bring Your Own IP (BYOIP) for IPv6 with an existing IPv6 prefix allocation.

## Prerequisites

1. **IPv6 Address Block**: An IPv6 prefix allocation (e.g., `/48` or `/44`) assigned by a Regional Internet Registry (RIR)
2. **RIR Authorization**: ROA (Route Origin Authorization) configured with the appropriate RIR
3. **AWS Account**: With appropriate IAM permissions to provision IPv6 pools

## Step 1: Prepare ROA (Route Origin Authorization)

Before AWS can advertise the prefix, it must be authorized via ROA with the appropriate Regional Internet Registry (RIR).

### For RIPE (Europe):

1. Log into the RIPE NCC portal
2. Create a ROA for the IPv6 prefix (e.g., `2001:db8:1234::/48`)
3. Authorize AWS ASNs for the target regions:
   - **Most AWS regions**: AS16509
   - **GovCloud regions**: AS8987
   - See [AWS ASN list](https://docs.aws.amazon.com/general/latest/gr/aws-ip-ranges.html)

4. Set max prefix length appropriately (typically `/56` for VPC allocation from a `/48` block)

Example ROA entry:
```
Prefix: 2001:db8:1234::/48
ASN: AS16509
Max Length: 56
```

**Note**: ROA propagation can take 24-48 hours.

## Step 2: Create X.509 Self-Signed Certificate

AWS requires cryptographic proof of ownership via an X.509 certificate:

```bash
# Generate private key
openssl genrsa -out private-key.pem 2048

# Create certificate signing request (replace with actual prefix)
openssl req -new -key private-key.pem -out csr.pem \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=2001:db8:1234::\/48"

# Generate self-signed certificate (valid 365 days)
openssl x509 -req -days 365 -in csr.pem \
  -signkey private-key.pem -out certificate.pem

# View certificate
openssl x509 -in certificate.pem -text -noout
```

## Step 3: Create ROA Message

Create a signed message authorizing AWS to advertise the prefix:

```bash
# Create message file (adjust dates and CIDR as needed)
cat > roa-message.txt << 'EOF'
1|aws|2001:db8:1234::/48|20260222|20270222|ripe|SHA256|RSAPSS
EOF

# Sign the message
openssl dgst -sha256 -sigopt rsa_padding_mode:pss \
  -sigopt rsa_pss_saltlen:-1 -sign private-key.pem \
  -keyform PEM -out signature.bin roa-message.txt

# Convert to base64
openssl base64 -in signature.bin -out signature.txt -A
```

**Message format explanation:**
- `1` - Version
- `aws` - Recipient
- `2001:db8:1234::/48` - IPv6 CIDR block
- `20260222` - Valid from (YYYYMMDD)
- `20270222` - Valid until (YYYYMMDD)
- `ripe` - Registry identifier (use `arin`, `ripe`, `apnic`, `lacnic`, or `afrinic`)
- `SHA256` - Hash algorithm
- `RSAPSS` - Signature algorithm

## Step 4: Provision BYOIP IPv6 Pool in AWS

Use AWS CLI to provision the IPv6 address pool:

```bash
# Set the target region
export AWS_REGION=eu-central-1
export IPV6_CIDR="2001:db8:1234::/48"

# Provision the address pool
aws ec2 provision-byoip-cidr \
  --cidr $IPV6_CIDR \
  --cidr-authorization-context \
    Message="$(cat roa-message.txt)",Signature="$(cat signature.txt)" \
  --publicly-advertisable \
  --description "IPv6 BYOIP Pool" \
  --region $AWS_REGION

# Expected output:
# {
#   "ByoipCidr": {
#     "Cidr": "2001:db8:1234::/48",
#     "State": "pending-provision"
#   }
# }
```

## Step 5: Monitor Provisioning Status

Provisioning can take several hours:

```bash
# Check status
aws ec2 describe-byoip-cidrs \
  --max-results 10 \
  --region $AWS_REGION

# Wait for state: "provisioned"
```

States:
- `pending-provision` → `provisioned` (success)
- `pending-provision` → `failed-provision` (check ROA/certificate)

## Step 6: Advertise the CIDR

Once provisioned, advertise to make it active:

```bash
aws ec2 advertise-byoip-cidr \
  --cidr $IPV6_CIDR \
  --region $AWS_REGION

# Verify advertising state
aws ec2 describe-byoip-cidrs \
  --region $AWS_REGION \
  --query 'ByoipCidrs[?Cidr==`'$IPV6_CIDR'`]'

# Look for: "State": "advertised"
```

## Step 7: Get Pool ID

After advertising, retrieve the pool ID:

```bash
aws ec2 describe-ipv6-pools \
  --region $AWS_REGION \
  --query 'Ipv6Pools[].[PoolId,PoolCidrBlocks[0].Cidr]' \
  --output table

# Or query specific CIDR:
aws ec2 describe-byoip-cidrs \
  --region $AWS_REGION \
  --query 'ByoipCidrs[?Cidr==`'$IPV6_CIDR'`].{PoolId:PoolId,Cidr:Cidr,State:State}' \
  --output table
```

Save the **Pool ID** (format: `ipv6pool-ec2-XXXXXXXXXXXXXXXXXX`)

## Step 8: Configure OpenTofu

Create `terraform.tfvars`:

```hcl
# Use BYOIP IPv6
use_byoip_ipv6     = true
byoip_ipv6_pool_id = "ipv6pool-ec2-XXXXXXXXXXXXXXXXXX"  # From Step 7

# Option A: Specify exact /56 from the /48 allocation
byoip_ipv6_cidr = "2001:db8:1234::/56"

# Option B: Let AWS allocate /56 automatically from the pool
# byoip_ipv6_netmask_length = 56

cluster_name = "ethrc-rbtl-eks-cluster"
region       = "eu-central-1"
```

## Step 9: Deploy with OpenTofu

```bash
tofu init
tofu plan
tofu apply
```

The VPC will use the specified IPv6 prefix:
- VPC: `2001:db8:1234::/56`
- Private subnets: `2001:db8:1234:0::/64`, `2001:db8:1234:1::/64`, `2001:db8:1234:2::/64`
- Public subnets: `2001:db8:1234:64::/64`, `2001:db8:1234:65::/64`, `2001:db8:1234:66::/64`

## Step 10: Verify

```bash
# Check VPC IPv6 CIDR
tofu output vpc_ipv6_cidr

# Verify EKS nodes have IPv6 addresses
kubectl get nodes -o wide
```

## Switching Between BYOIP and AWS IPs

### Use AWS-provided IPv6 (default):
```hcl
# terraform.tfvars
use_byoip_ipv6 = false
```

### Use BYOIP:
```hcl
# terraform.tfvars
use_byoip_ipv6     = true
byoip_ipv6_pool_id = "ipv6pool-ec2-XXXXXXXXXXXXXXXXXX"
byoip_ipv6_cidr    = "2001:db8:1234::/56"
```

**⚠️ Warning**: Changing IPv6 addressing requires VPC recreation (destructive).

## Troubleshooting

### ROA Issues
```bash
# Verify ROA is visible globally (example for RIPE)
whois -h whois.ripe.net 2001:db8:1234::

# Check BGP route object
whois -h whois.ripe.net -r -T route6 2001:db8:1234::/48
```

### Provisioning Failures

Common issues:
1. **Invalid ROA**: ASN not authorized, max-length too restrictive
2. **Certificate mismatch**: CIDR in cert doesn't match provision request
3. **Expired message**: Check dates in ROA message
4. **Wrong registry**: Use `ripe` not `arin` in message

### Verify Advertisement

```bash
# Check with external BGP looking glass
# Example: view from Hurricane Electric
# https://lg.he.net/

# Or use AWS validation
aws ec2 describe-byoip-cidrs \
  --region $AWS_REGION \
  --query 'ByoipCidrs[*].[Cidr,State,StatusMessage]' \
  --output table
```

## Costs

- **BYOIP IPv6**: No additional cost
- **Provisioning**: Free
- **Data transfer**: Same as regular IPv6

## Cleanup / De-provisioning

To stop using BYOIP and remove the pool from AWS:

```bash
# 1. Stop advertising
aws ec2 withdraw-byoip-cidr \
  --cidr $IPV6_CIDR \
  --region $AWS_REGION

# 2. Wait for "provisioned" state (no longer "advertised")

# 3. Deprovision
aws ec2 deprovision-byoip-cidr \
  --cidr $IPV6_CIDR \
  --region $AWS_REGION
```

**Note**: All resources using the BYOIP pool must be deleted before deprovisioning.

## References

- [AWS BYOIP Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-byoip.html)
- [AWS IPv6 BYOIP Guide](https://docs.aws.amazon.com/vpc/latest/userguide/working-with-vpcs.html#vpc-associate-ipv6-cidr)
- [RIPE ROA Management](https://www.ripe.net/manage-ips-and-asns/resource-management/certification)
- [AWS IP Ranges & ASNs](https://docs.aws.amazon.com/general/latest/gr/aws-ip-ranges.html)
