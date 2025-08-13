# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository provides automated deployment of Proxmox VE 7 on AWS EC2 instances using cloud-init automation. It enables running a complete Proxmox virtualization environment in AWS with minimal manual configuration.

## Core Architecture

### Deployment Process
The deployment follows a cloud-init driven automation pattern:

1. **AMI Selection**: Uses official Debian 11 AMD64 AMIs as base images
2. **Cloud-Init Configuration**: The `cloud-init.yaml` file orchestrates the entire Proxmox installation
3. **Network Configuration**: Automatically configures bridges and NAT for guest networking
4. **Package Installation**: Installs Proxmox VE packages and dependencies via Debian repositories

### Key Components

**cloud-init.yaml**: The core automation script that:
- Adds Proxmox APT repository and GPG keys
- Installs Proxmox VE, postfix, and open-iscsi packages
- Patches ifupdown2 scheduler for environment variable handling
- Configures network interfaces with NAT bridge (vmbr0) at 10.10.10.1/24
- Sets up dnsmasq DHCP server for guest networking
- Disables IPv6 to prevent DHCPv6 timeout issues
- Replaces default 127.0.1.1 hostname resolution with EC2 private IP

**Network Architecture**: 
- Primary interface: EC2-managed with DHCP
- Bridge vmbr0: NAT network (10.10.10.0/24) for guest VMs/containers
- Optional vmbr1: Routed network for guests with dedicated AWS private IPs
- iptables NAT rules for internet access from guest networks

## Common AWS Commands

### Deploying Proxmox Instance
```bash
# Get latest Debian 11 AMI ID
aws ssm get-parameter --name /aws/service/debian/daily/bullseye/latest/amd64 --query 'Parameter.Value' --output text

# Launch instance with cloud-init
aws ec2 run-instances \
    --image-id <AMI_ID> \
    --instance-type c5.2xlarge \
    --key-name <YOUR_KEY_NAME> \
    --security-group-ids <SECURITY_GROUP_ID> \
    --user-data file://cloud-init.yaml
```

### Instance Management
```bash
# Check instance status
aws ec2 describe-instances --instance-ids <INSTANCE_ID>

# Monitor cloud-init progress (via SSH)
ssh -i <KEY_FILE> root@<PUBLIC_IP> "tail -f /var/log/cloud-init-output.log"

# Set root password for Proxmox web console
ssh -i <KEY_FILE> root@<PUBLIC_IP> "passwd"
```

### Cleanup
```bash
# Terminate instance
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>

# Delete security group
aws ec2 delete-security-group --group-id <SECURITY_GROUP_ID>

# Delete key pair
aws ec2 delete-key-pair --key-name <KEY_NAME>
```

## Critical Configuration Details

### Instance Type Requirements
- **Containers only**: Minimum t3.small (2GB RAM), avoid t3.micro (insufficient memory)
- **VM guests**: Requires metal instances (c5n.metal, m5zn.metal) for hardware virtualization support
- Metal instances cost ~$4/hour, use Spot Instances for cost reduction

### Security Considerations
- Always restrict security groups to specific IP addresses, never 0.0.0.0/0
- Proxmox web interface runs on port 8006 (HTTPS)
- SSH access required for initial root password setup
- Network configuration must be done manually via `/etc/network/interfaces`, NOT through Proxmox GUI

### Network Configuration Constraints
- EC2 network interfaces are managed by cloud-init templates
- Editing network config through Proxmox GUI breaks connectivity
- Always edit `/etc/network/interfaces` manually
- Use `systemctl restart networking.service` to apply changes
- IPv6 is disabled to prevent cloud-init timeouts

### Post-Installation Requirements
1. SSH to instance and run `passwd` to set root password
2. Access web console at `https://<PUBLIC_IP>:8006/`
3. **CRITICAL**: Reboot instance after first login to activate Proxmox kernel
4. Without reboot, containers fail with AppArmor errors

## Guest Networking Modes

### NAT Guests (Default)
- Use bridge vmbr0 (10.10.10.0/24)
- Automatic DHCP via dnsmasq
- Internet access via host NAT
- Not accessible from external AWS network

### Routed Guests (Advanced)
- Requires additional private IPs on ENI
- Use bridge vmbr1 with manual IP assignment
- Direct access from VPC network
- Requires Elastic IPs for public internet access

## Troubleshooting Commands

### Installation Monitoring
```bash
# Check cloud-init status
systemctl status cloud-final.service

# View installation logs
tail -f /var/log/cloud-init-output.log
tail -f /var/log/syslog

# Verify Proxmox installation
systemctl status pve*
```

### Network Debugging
```bash
# Check network interface status
ip addr show
systemctl status networking.service

# Verify bridge configuration
brctl show
ip route show table local
```

### Common Issues
- AMI not found: Use region-specific AMI lookup
- SSH timeout: Instance may be slow to boot, check EC2 console
- Cloud-init failures: Check for YAML syntax errors in cloud-init.yaml
- Network broken after GUI changes: Restore `/etc/network/interfaces` from backup