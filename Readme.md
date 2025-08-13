# Proxmox VE 8 on AWS Outpost Deployment

Automated deployment of Proxmox VE 8 on AWS EC2 instances using cloud-init. This project enables you to run a complete Proxmox virtualization environment on AWS with minimal manual configuration.

## What is This?

This repository provides a streamlined way to deploy Proxmox VE 8 on AWS EC2 instances. Using automated cloud-init scripts, you can have a fully functional Proxmox environment running in minutes, perfect for labs, development, or production workloads.

**Key Features:**
- Automated Proxmox VE 8 installation on Debian 12
- Pre-configured NAT networking for guest VMs/containers
- Support for both container and full VM workloads
- AWS-optimized network configuration
- One-command deployment via AWS CLI

## Prerequisites

Before you begin, you should have:

- **AWS Account** with EC2 access and appropriate permissions
- **AWS CLI** installed and configured with your credentials
- **Basic familiarity** with virtualization concepts
- **SSH key pair** for EC2 access

**What is Proxmox VE?** Proxmox Virtual Environment is an open-source virtualization platform that combines KVM (for virtual machines) and LXC (for containers) with a web-based management interface.

**What are AWS Outposts?** AWS Outposts bring native AWS services and infrastructure to your on-premises locations, but this project works on standard EC2 as well.

## Quick Start

### Option 1: One-Command Deployment

```bash
# Get the latest Debian 12 AMI
DEBIAN_AMI=$(aws ssm get-parameter --name /aws/service/debian/daily/bookworm/latest/amd64 --query 'Parameter.Value' --output text)

# Create a security group (replace YOUR_IP with your actual IP)
SG_ID=$(aws ec2 create-security-group \
  --group-name proxmox-sg \
  --description "Proxmox VE Security Group" \
  --query 'GroupId' --output text)

# Allow SSH and Proxmox web access from your IP only
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 22 --cidr YOUR_IP/32

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 8006 --cidr YOUR_IP/32

# Launch the instance
aws ec2 run-instances \
  --image-id $DEBIAN_AMI \
  --instance-type t3.small \
  --key-name YOUR_KEY_NAME \
  --security-group-ids $SG_ID \
  --user-data file://cloud-init-deb-12-proxmox-8.yaml \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Proxmox-VE}]'
```

### Option 2: Step-by-Step Deployment

1. **Get the latest Debian 12 AMI**:
   ```bash
   aws ssm get-parameter --name /aws/service/debian/daily/bookworm/latest/amd64 --query 'Parameter.Value' --output text
   ```

2. **Launch EC2 instance** with:
   - **AMI**: Use the Debian 12 AMI from step 1
   - **Instance Type**: `t3.small` minimum (2GB RAM) - avoid `t3.micro`
   - **Key Pair**: Your existing SSH key pair
   - **Security Group**: Allow TCP 22 (SSH) and 8006 (Proxmox) from your IP only
   - **User Data**: Contents of `cloud-init-deb-12-proxmox-8.yaml`

3. **Monitor installation** (~7-10 minutes):
   ```bash
   # Get your instance IP
   INSTANCE_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=Proxmox-VE" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
   
   # Monitor progress via SSH
   ssh -i your-key.pem root@$INSTANCE_IP "tail -f /var/log/cloud-init-output.log"
   ```

4. **Set root password**:
   ```bash
   ssh -i your-key.pem root@$INSTANCE_IP "passwd"
   ```

5. **Access Proxmox Web UI**: Visit `https://YOUR_INSTANCE_IP:8006/`
   - Username: `root`
   - Password: The password you just set

6. **Reboot after first login**:
   ```bash
   ssh -i your-key.pem root@$INSTANCE_IP "reboot"
   ```
   This activates the Proxmox kernel and prevents container launch issues.

### Instance Type Selection

| Use Case | Recommended Instance | Notes |
|----------|---------------------|--------|
| **Containers Only** | `t3.small` or larger | Minimum 2GB RAM required |
| **Virtual Machines** | `c5n.metal`, `m5zn.metal` | Requires hardware virtualization (~$4/hour) |

⚠️ **Important**: `t3.micro` (1GB RAM) will freeze under load. Metal instances are expensive but required for VM guests with hardware acceleration.

## Understanding Network Configuration

The automated setup creates a network configuration optimized for AWS. Here's what gets configured automatically:

### Automatic Network Setup

**Primary Interface (`eth0` or similar):**
- Managed by AWS with DHCP
- Gets your instance's private IP from AWS
- Handles internet connectivity

**NAT Bridge (`vmbr0`):**
- Internal network: `10.10.10.0/24`
- Gateway: `10.10.10.1` (the Proxmox host)
- DHCP server provides IPs `10.10.10.2` - `10.10.10.254`
- All guest traffic is NAT'd through the host's primary interface

### For Your Guests (VMs/Containers)

**Simple Setup (Recommended):**
1. Attach guests to bridge `vmbr0`
2. Enable DHCP in guest network settings
3. Guests automatically get internet access

**What This Means:**
- ✅ Guests can access the internet
- ✅ Guests can communicate with each other
- ✅ Host can access guests via their 10.10.10.x IPs
- ❌ External AWS resources cannot directly access guests
- ❌ Guests don't have "real" AWS IP addresses

### Critical Network Rules

⚠️ **NEVER edit network settings through the Proxmox web interface** - this will break connectivity!

**Always edit `/etc/network/interfaces` manually via SSH:**
```bash
ssh -i your-key.pem root@YOUR_IP
nano /etc/network/interfaces
systemctl restart networking.service
```

### Advanced: Direct Guest Access (Optional)

If you need external AWS resources to access your guests directly, see the "Advanced Networking" section below.

## Virtual Machine Requirements

### For Container Workloads
- **Instance Types**: `t3.small` or larger
- **Minimum RAM**: 2GB (avoid `t3.micro`)
- **Cost**: Starting ~$0.02/hour
- **What You Get**: LXC containers, perfect for microservices, web apps, databases

### For Full Virtual Machines
- **Instance Types**: `c5n.metal`, `m5zn.metal`, etc.
- **Requirements**: Hardware virtualization support (VT-x/AMD-V)
- **Cost**: ~$4/hour (use Spot Instances for 75% savings)
- **What You Get**: Full VMs with hardware acceleration

**Why Metal Instances?** Standard EC2 instances run on hypervisors that don't expose hardware virtualization features. Metal instances give you direct hardware access, enabling nested virtualization.

**Alternative**: You can run VMs on standard instances by disabling KVM in the VM's Options tab, but performance will be extremely poor.

## Advanced Networking: Direct Guest Access

By default, guests use NAT networking and aren't directly accessible from AWS. If you need AWS resources to directly access your guests, you can configure routed networking.

### When You Need This
- Database servers that AWS resources need to access
- Web services that need AWS Application Load Balancer integration  
- Microservices that need direct VPC communication

### Setup Process

**1. Assign Additional Private IPs to Your Instance**

Check your instance type's ENI limits: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html

For `t3.small`: 1 primary + 3 additional IPs (4 total)

```bash
# Add additional private IPs to your instance
aws ec2 assign-private-ip-addresses \
  --network-interface-id <YOUR_ENI_ID> \
  --private-ip-addresses 172.31.14.9 172.31.14.10 172.31.14.11
```

**2. Configure Bridge on Proxmox Host**

SSH to your Proxmox instance and edit `/etc/network/interfaces`:

```bash
# Add this to the end of /etc/network/interfaces
auto vmbr1
iface vmbr1 inet static
    address 172.31.14.8/29  # First IP in your range
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up echo 1 > /proc/sys/net/ipv4/conf/eth0/proxy_arp

# Apply changes
systemctl restart networking.service
```

**3. Configure Guests**

For each guest:
- Attach to bridge `vmbr1`
- Set static IP: `172.31.14.9/29`, `172.31.14.10/29`, etc.
- Gateway: `172.31.14.8` (the bridge IP)
- DNS: `169.254.169.253` (AWS VPC DNS)

**4. Optional: Public IP Access**

To give guests internet access, associate Elastic IPs:

```bash
aws ec2 associate-address \
  --instance-id <INSTANCE_ID> \
  --private-ip-address 172.31.14.9 \
  --allocation-id <ELASTIC_IP_ALLOCATION_ID>
```

### Security Considerations
- Instance security group applies to ALL guests
- Use Proxmox firewall for guest-specific rules
- Consider dedicated security groups per workload

## Troubleshooting

### Installation Issues

**Problem**: Cloud-init fails or hangs
```bash
# Check cloud-init status
ssh -i your-key.pem root@YOUR_IP "systemctl status cloud-final.service"

# View installation logs
ssh -i your-key.pem root@YOUR_IP "tail -f /var/log/cloud-init-output.log"
```

**Problem**: Can't access Proxmox web interface
- ✅ Check security group allows TCP 8006 from your IP
- ✅ Verify instance is running and cloud-init completed
- ✅ Try accessing via private IP if on VPN/direct connect

**Problem**: Instance appears frozen
- Likely cause: `t3.micro` with insufficient RAM
- Solution: Stop instance, change to `t3.small`, restart

### Container/VM Issues

**Problem**: Containers fail to start with AppArmor errors
```bash
# Reboot to activate Proxmox kernel
ssh -i your-key.pem root@YOUR_IP "reboot"
```

**Problem**: Guests can't access internet
- ✅ Verify guest attached to `vmbr0`
- ✅ Enable DHCP in guest network settings
- ✅ Check guest received IP in 10.10.10.x range

### Network Connectivity

**Problem**: Lost SSH access after network changes
```bash
# Use EC2 Serial Console to recover
# Fix /etc/network/interfaces manually
# Restart networking: systemctl restart networking.service
```

**Problem**: Guests can't reach each other
- ✅ Ensure all guests on same bridge (`vmbr0`)
- ✅ Check Proxmox firewall rules
- ✅ Verify DHCP assigned IPs correctly

### Performance Issues

**Problem**: Slow VM performance
- For full VMs: Use metal instances with hardware virtualization
- For containers: Increase instance size or optimize container resources

### Common Commands

```bash
# Check Proxmox services
systemctl status pve*

# View network configuration
ip addr show
brctl show

# Monitor resource usage
htop
df -h

# Check guest IPs
cat /var/lib/dhcp/dhcpd.leases  # If using DHCP
```

## Creating Custom AMIs

You can create custom AMIs from your configured Proxmox instance for faster future deployments:

```bash
# Create AMI from your running instance
aws ec2 create-image \
  --instance-id <YOUR_INSTANCE_ID> \
  --name "Proxmox-VE-8-Custom" \
  --description "Pre-configured Proxmox VE 8 on Debian 12"
```

**Important**: If you plan to change hostnames on AMI-launched instances, ensure no VMs/containers exist (see [Proxmox node renaming guide](https://pve.proxmox.com/wiki/Renaming_a_PVE_node)).

**Launch from custom AMI** with hostname override:
```bash
aws ec2 run-instances \
  --image-id <YOUR_CUSTOM_AMI> \
  --instance-type t3.small \
  --key-name YOUR_KEY_NAME \
  --security-group-ids <SG_ID> \
  --user-data $'#cloud-config\nhostname: proxmox\nfqdn: proxmox.local'
```

## Cleanup Resources

When you're done testing, clean up to avoid charges:

```bash
# Terminate instance
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>

# Delete security group (after instance terminates)
aws ec2 delete-security-group --group-id <SECURITY_GROUP_ID>

# Release Elastic IPs (if used)
aws ec2 release-address --allocation-id <ALLOCATION_ID>
```

## Legacy Support

For older deployments, Debian 11 with Proxmox VE 7 is still available:

```bash
# Use legacy configuration
aws ec2 run-instances \
  --image-id $(aws ssm get-parameter --name /aws/service/debian/daily/bullseye/latest/amd64 --query 'Parameter.Value' --output text) \
  --instance-type t3.small \
  --user-data file://cloud-init-deb-11-proxmox-7.yaml \
  # ... other parameters
```

The Debian 12/Proxmox 8 configuration is recommended for new deployments due to improved security, performance, and longer support lifecycle.

## Further Reading

- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [AWS EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [AWS Networking Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [Metal Instance Pricing](https://instances.vantage.sh/?filter=metal)
