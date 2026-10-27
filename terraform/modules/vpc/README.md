# vpc

Wrapper around [`terraform-aws-modules/vpc`](https://github.com/terraform-aws-modules/terraform-aws-vpc)
(v6.7.3). It encodes the decisions below; it is not a pass-through.

## CIDR plan

**VPC: `10.20.0.0/16`** (65,536 addresses).

- The subnets below use about 19% of it. The rest is room for another tier or a secondary CIDR
  without re-addressing.
- No overlap with the other VPCs in the account, Docker's bridge (`172.17.0.0/16`), or EKS's
  default service ranges (`10.100.0.0/16`, `172.20.0.0/16`). The EKS module sets the service CIDR
  explicitly anyway, because it can't be changed after the cluster is created.
- Deliberately not a common default. `10.0.0.0/16` and `10.10.0.0/16` are what most hand-made VPCs
  use, and the usual Kubernetes ranges are taken too: kubeadm services `10.96.0.0/12`, Flannel
  pods `10.244.0.0/16`, k3s `10.42.0.0/16` and `10.43.0.0/16`, Calico and home LANs
  `192.168.0.0/16`. Peering or a VPN later needs no re-addressing.

## Subnets

Three AZs, given as **AZ IDs** (IDs map to the same physical zone in every account; names like
`us-east-1a` don't). `use1-az3` is excluded: EKS rejects cluster subnets there
(`UnsupportedAvailabilityZoneException`), and `t4g.large` isn't offered there either.

| Tier | AZ ID | CIDR | Usable IPs | What lives there |
|---|---|---|---|---|
| private | use1-az1 | `10.20.0.0/20` | 4,091 | nodes, pods, EKS control-plane ENIs |
| private | use1-az2 | `10.20.16.0/20` | 4,091 | nodes, pods, EKS control-plane ENIs |
| private | use1-az4 | `10.20.32.0/20` | 4,091 | nodes, pods, EKS control-plane ENIs |
| public | use1-az1 | `10.20.48.0/24` | 251 | ALB, NAT gateway |
| public | use1-az2 | `10.20.49.0/24` | 251 | ALB |
| public | use1-az4 | `10.20.50.0/24` | 251 | ALB |

- Usable = total − 5. AWS reserves the network address, the VPC router, DNS, one future
  address and the broadcast address in every subnet.
- **Public subnets must be at least /27.** An ALB needs a /27 or larger, with at least 8 free IPs per
  subnet so it can scale out; when it can't, it returns 5xx errors or times out. /24 costs nothing
  extra in a private address space and keeps the addressing readable.
- No separate intra tier: the control-plane ENIs go in the private subnets. Add one only if
  something needs subnets with no route out.
- Tags for load balancer discovery: public `kubernetes.io/role/elb = 1`, private
  `kubernetes.io/role/internal-elb = 1`.

## Pod density

**VPC CNI prefix delegation, on `t4g.large` nodes** (Graviton, 2 vCPU, 8 GiB, 3 ENIs, 12 IPv4
per ENI).

Why prefix mode: without it, each pod uses one secondary IP slot on an ENI, so a node runs out of
slots before it runs out of CPU or memory. With it, each slot holds a /28 (16 IPs) instead of one.

| | Secondary-IP mode | Prefix mode |
|---|---|---|
| Formula | ENIs × (IPs per ENI − 1) + 2 | ENIs × (IPs per ENI − 1) × 16 + 2 |
| t4g.large | 3 × 11 + 2 = **35** | 3 × 11 × 16 + 2 = 530 → capped at **110** |

- The +2 is `aws-node` and `kube-proxy`, which use the host network and take no pod IP.
- Managed node groups cap max pods at 110 below 30 vCPUs. On a 2 vCPU node, CPU and memory run
  out before 110 pods anyway.
- Prefix delegation must be enabled on the VPC CNI add-on **before** the node group is created.
  Nodes calculate max pods at launch, so enabling it later means replacing them.

**IPs one node takes from its subnet (worst case):**

- 108 pod IPs (110 − 2 host-network pods) need ⌈108 / 16⌉ = 7 prefixes.
- `WARM_PREFIX_TARGET = 1` (the default) holds 1 more: 8 prefixes × 16 = 128.
- Plus the node's own primary IP: **129 IPs per node**.

**Per private subnet:** 4,091 / 129 ≈ **31 nodes per AZ** before the subnet is full. The plan is a
few nodes in total, plus surge nodes during a rollout and up to 4 temporary ENIs during an EKS
upgrade.

The /20 is sized for **contiguity, not count**. A prefix must be a contiguous, aligned /28. A /20
holds 256 of them, and scattered node IPs and ENIs fragment them over time; prefix attachment fails
on a fragmented subnet even when free IPs remain. If that happens, the fix is a subnet CIDR
reservation for prefixes.

Carried into later stages: Graviton nodes are `arm64`, so every image (the app, and each Helm
chart's images) must have an `arm64` or multi-arch build.

## NAT strategy

**One NAT gateway, in the use1-az1 public subnet**, shared by all three private subnets. The
wrapper exposes this as one choice (`single` or `per_az`).

| Option | $/hour | $/month (730 h) | When the NAT's AZ fails |
|---|---|---|---|
| single (chosen) | $0.045 | $32.85 | all three AZs lose egress |
| per_az | $0.135 | $98.55 | only that AZ loses egress |
| regional | $0.045 per AZ | — | not supported by the module (v6.7.3) |

Plus $0.045 per GB processed, in every option.

- **Cost note:** one NAT left up for a whole month costs more than the $30 budget on its own.
  The cluster is destroyed after each session.
- **What a user sees when use1-az1 fails:** pods that are already running keep serving through the
  ALB, because inbound traffic doesn't pass through the NAT. Anything that needs the internet
  fails in all AZs: image pulls from public registries (new pods sit in `ImagePullBackOff`, so
  deploys and scale-ups stop), and AWS API calls from pods. It lasts as long as the AZ outage, or
  until the NAT is moved to a surviving AZ with one `apply` (minutes).
- **Keeps the cluster up through that failure:** EKS private endpoint access, so nodes reach the API
  server inside the VPC instead of through the NAT (set in the EKS module).
- **S3 gateway endpoint (free):** ECR serves image layers from S3, so image pulls skip the NAT and
  its per-GB charge.
