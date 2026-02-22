# BYOIP IPv6

Use a BYOIP IPv6 prefix instead of AWS-provided addresses.

> **Warning:** Changing IPv6 addressing after initial deploy requires VPC recreation (destructive). Decide before first apply.

## Prerequisites

- An IPv6 prefix allocation (`/48` or larger) from a Regional Internet Registry (RIR)
- ROA (Route Origin Authorization) configured with your RIR authorizing AWS ASN `16509` (or `8987` for GovCloud)
- ROA propagation can take 24–48 hours

Example ROA entry (RIPE):
```
Prefix:     2001:db8:1234::/48
ASN:        AS16509
Max Length: 56
```

---

## Provision the pool in AWS

### 1. Create an X.509 certificate

AWS requires proof of prefix ownership:

```bash
openssl genrsa -out private-key.pem 2048

openssl req -new -key private-key.pem -out csr.pem \
  -subj "/C=US/O=YourOrg/CN=2001:db8:1234::\/48"

openssl x509 -req -days 365 -in csr.pem \
  -signkey private-key.pem -out certificate.pem
```

### 2. Create and sign the ROA message

```bash
# Adjust dates (YYYYMMDD) and registry (arin | ripe | apnic | lacnic | afrinic)
cat > roa-message.txt << 'EOF'
1|aws|2001:db8:1234::/48|20260222|20270222|ripe|SHA256|RSAPSS
EOF

openssl dgst -sha256 -sigopt rsa_padding_mode:pss \
  -sigopt rsa_pss_saltlen:-1 -sign private-key.pem \
  -keyform PEM -out signature.bin roa-message.txt

openssl base64 -in signature.bin -out signature.txt -A
```

### 3. Provision and advertise

```bash
export AWS_REGION=eu-central-1
export IPV6_CIDR="2001:db8:1234::/48"

aws ec2 provision-byoip-cidr \
  --cidr $IPV6_CIDR \
  --cidr-authorization-context \
    Message="$(cat roa-message.txt)",Signature="$(cat signature.txt)" \
  --publicly-advertisable \
  --region $AWS_REGION

# Provisioning takes several hours. Poll until state = "provisioned":
aws ec2 describe-byoip-cidrs --max-results 10 --region $AWS_REGION

# Then advertise:
aws ec2 advertise-byoip-cidr --cidr $IPV6_CIDR --region $AWS_REGION
```

### 4. Get the pool ID

```bash
aws ec2 describe-ipv6-pools \
  --region $AWS_REGION \
  --query 'Ipv6Pools[].[PoolId,PoolCidrBlocks[0].Cidr]' \
  --output table
```

Save the pool ID — it looks like `ipv6pool-ec2-XXXXXXXXXXXXXXXXXX`.

---

## Configure OpenTofu

In `terraform.tfvars`:

```hcl
use_byoip_ipv6     = true
byoip_ipv6_pool_id = "ipv6pool-ec2-XXXXXXXXXXXXXXXXXX"

# Option A: specify exact /56
byoip_ipv6_cidr = "2001:db8:1234::/56"

# Option B: let AWS pick a /56 from the pool
# byoip_ipv6_netmask_length = 56
```

Then deploy normally — see [QUICKSTART.md](QUICKSTART.md).

Resulting subnet layout (Option A):
- Private: `2001:db8:1234:0::/64`, `…:1::/64`, `…:2::/64`
- Public:  `2001:db8:1234:64::/64`, `…:65::/64`, `…:66::/64`

---

## Troubleshooting

**Provisioning fails**
- Check ROA: ASN must be `16509`, max-length must be `≤ 56`
- Check cert: CN must match the CIDR exactly
- Check message: dates must be valid and not expired
- Check registry: use `ripe`, not `arin`, if your allocation is from RIPE

```bash
# Verify ROA visibility
whois -h whois.ripe.net -r -T route6 2001:db8:1234::/48

# Check provisioning status and error message
aws ec2 describe-byoip-cidrs \
  --region $AWS_REGION \
  --query 'ByoipCidrs[*].[Cidr,State,StatusMessage]' \
  --output table
```

---

## Deprovision

All resources using the pool must be destroyed first, then:

```bash
aws ec2 withdraw-byoip-cidr --cidr $IPV6_CIDR --region $AWS_REGION
# wait for state = "provisioned"
aws ec2 deprovision-byoip-cidr --cidr $IPV6_CIDR --region $AWS_REGION
```

---

## References

- [AWS BYOIP docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-byoip.html)
- [AWS IP ranges & ASNs](https://docs.aws.amazon.com/general/latest/gr/aws-ip-ranges.html)
- [RIPE ROA management](https://www.ripe.net/manage-ips-and-asns/resource-management/certification)
