#!/bin/bash

# Proxmox VE on EC2 Deployment Test Script
# This script automates the entire deployment and testing workflow

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/test-$(date +%Y%m%d-%H%M%S).log"
INSTANCE_TYPE="${INSTANCE_TYPE:-c5.2xlarge}"
VOLUME_SIZE="${VOLUME_SIZE:-64}"
CLOUD_INIT_FILE="${CLOUD_INIT_FILE:-proxmox-on-ec2/cloud-init-modified.yaml}"
TEST_TIMEOUT="${TEST_TIMEOUT:-600}"  # 10 minutes
ROOT_PASSWORD="ProxmoxTest123!"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
INSTANCE_ID=""
PUBLIC_IP=""
KEY_NAME=""
SECURITY_GROUP_ID=""
CLEANUP_RESOURCES=()

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "${RED}ERROR: $1${NC}"
    cleanup_resources
    exit 1
}

# Success message
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Cleanup function
cleanup_resources() {
    if [[ "${CLEANUP_ON_FAILURE:-true}" == "true" ]]; then
        info "Cleaning up resources..."
        
        if [[ -n "$INSTANCE_ID" ]]; then
            info "Terminating instance: $INSTANCE_ID"
            aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null 2>&1 || true
        fi
        
        if [[ -n "$KEY_NAME" ]]; then
            info "Deleting key pair: $KEY_NAME"
            aws ec2 delete-key-pair --key-name "$KEY_NAME" >/dev/null 2>&1 || true
            rm -f "${KEY_NAME}.pem" || true
        fi
        
        if [[ -n "$SECURITY_GROUP_ID" ]]; then
            info "Deleting security group: $SECURITY_GROUP_ID"
            # Wait a bit for instance to terminate
            sleep 10
            aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID" >/dev/null 2>&1 || true
        fi
    else
        info "Cleanup disabled. Resources left running for manual inspection."
        info "Instance ID: $INSTANCE_ID"
        info "Public IP: $PUBLIC_IP"
        info "Key file: ${KEY_NAME}.pem"
    fi
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI not found. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS credentials not configured or invalid."
    fi
    
    # Check cloud-init file exists
    if [[ ! -f "$CLOUD_INIT_FILE" ]]; then
        error_exit "Cloud-init file not found: $CLOUD_INIT_FILE"
    fi
    
    success "Prerequisites check passed"
}

# Get latest Debian 11 AMI
get_debian_ami() {
    info "Getting latest Debian 11 AMI..."
    
    local ami_id
    ami_id=$(aws ec2 describe-images \
        --owners 136693071363 \
        --filters "Name=name,Values=debian-11-amd64-*" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [[ "$ami_id" == "None" || -z "$ami_id" ]]; then
        error_exit "Could not find Debian 11 AMI"
    fi
    
    success "Found Debian 11 AMI: $ami_id"
    echo "$ami_id"
}

# Create SSH key pair
create_key_pair() {
    info "Creating SSH key pair..."
    
    KEY_NAME="proxmox-test-$(date +%s)"
    
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text > "${KEY_NAME}.pem"
    
    chmod 600 "${KEY_NAME}.pem"
    
    success "Created key pair: $KEY_NAME"
}

# Create security group
create_security_group() {
    info "Creating security group..."
    
    local my_ip
    my_ip=$(curl -s https://checkip.amazonaws.com)
    
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "proxmox-test-$(date +%s)" \
        --description "Security group for Proxmox VE test" \
        --query 'GroupId' \
        --output text)
    
    # Add SSH rule
    aws ec2 authorize-security-group-ingress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 22 \
        --cidr "${my_ip}/32" >/dev/null
    
    # Add Proxmox web interface rule
    aws ec2 authorize-security-group-ingress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 8006 \
        --cidr "${my_ip}/32" >/dev/null
    
    success "Created security group: $SECURITY_GROUP_ID (allowing access from $my_ip)"
}

# Launch EC2 instance
launch_instance() {
    local ami_id="$1"
    info "Launching EC2 instance ($INSTANCE_TYPE)..."
    
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --count 1 \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --user-data "file://$CLOUD_INIT_FILE" \
        --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3}" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Proxmox-Test-$(date +%s)}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    success "Launched instance: $INSTANCE_ID"
}

# Wait for instance to be running
wait_for_instance() {
    info "Waiting for instance to be running..."
    
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    success "Instance running with public IP: $PUBLIC_IP"
}

# Wait for SSH to be available
wait_for_ssh() {
    info "Waiting for SSH to be available..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" "echo 'SSH ready'" >/dev/null 2>&1; then
            success "SSH is available"
            return 0
        fi
        
        info "SSH attempt $attempt/$max_attempts failed, waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    error_exit "SSH never became available after $max_attempts attempts"
}

# Wait for cloud-init to complete
wait_for_cloud_init() {
    info "Waiting for cloud-init to complete..."
    
    local max_attempts=60  # 10 minutes
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" "sudo cloud-init status --format=json 2>/dev/null | jq -r '.status' 2>/dev/null || echo 'unknown'")
        
        case "$status" in
            "done")
                success "Cloud-init completed successfully"
                return 0
                ;;
            "error")
                warning "Cloud-init completed with errors, continuing..."
                return 0
                ;;
            "running")
                info "Cloud-init still running (attempt $attempt/$max_attempts)..."
                ;;
            *)
                info "Cloud-init status unknown (attempt $attempt/$max_attempts)..."
                ;;
        esac
        
        sleep 10
        ((attempt++))
    done
    
    error_exit "Cloud-init did not complete within expected time"
}

# Set root password
set_root_password() {
    info "Setting root password..."
    
    ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" \
        "echo 'root:$ROOT_PASSWORD' | sudo chpasswd"
    
    success "Root password set"
}

# Reboot system to switch to Proxmox kernel
reboot_system() {
    info "Rebooting system to switch to Proxmox kernel..."
    
    ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" "sudo reboot" || true
    
    # Wait for system to go down
    sleep 30
    
    # Wait for system to come back up
    wait_for_ssh
    
    success "System rebooted successfully"
}

# Test Proxmox installation
test_proxmox_installation() {
    info "Testing Proxmox installation..."
    
    # Check if Proxmox packages are installed
    local proxmox_packages
    proxmox_packages=$(ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" \
        "dpkg -l | grep -c proxmox || echo 0")
    
    if [[ "$proxmox_packages" -lt 5 ]]; then
        error_exit "Proxmox packages not properly installed (found $proxmox_packages packages)"
    fi
    
    success "Proxmox packages installed ($proxmox_packages packages found)"
    
    # Check Proxmox kernel
    local kernel
    kernel=$(ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" "uname -r")
    
    if [[ "$kernel" != *"pve"* ]]; then
        error_exit "Not running Proxmox kernel: $kernel"
    fi
    
    success "Running Proxmox kernel: $kernel"
    
    # Check pveproxy service
    if ! ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" \
        "sudo systemctl is-active pveproxy >/dev/null 2>&1"; then
        error_exit "Proxmox web service (pveproxy) is not running"
    fi
    
    success "Proxmox web service is running"
}

# Test web interface
test_web_interface() {
    info "Testing Proxmox web interface..."
    
    # Test HTTPS connection
    local http_status
    http_status=$(curl -k -s -o /dev/null -w "%{http_code}" "https://$PUBLIC_IP:8006/" || echo "000")
    
    if [[ "$http_status" != "200" ]]; then
        error_exit "Web interface not responding correctly (HTTP $http_status)"
    fi
    
    success "Web interface is accessible"
    
    # Test login page content
    local page_content
    page_content=$(curl -k -s "https://$PUBLIC_IP:8006/" | grep -c "Proxmox Virtual Environment" || echo 0)
    
    if [[ "$page_content" -eq 0 ]]; then
        error_exit "Web interface not showing Proxmox content"
    fi
    
    success "Web interface showing correct Proxmox content"
}

# Test network configuration
test_network_config() {
    info "Testing network configuration..."
    
    # Check vmbr0 bridge
    if ! ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" \
        "sudo ip addr show vmbr0 | grep -q '10.10.10.1/24'"; then
        error_exit "vmbr0 bridge not configured correctly"
    fi
    
    success "vmbr0 bridge configured correctly"
    
    # Check dnsmasq DHCP server
    if ! ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" \
        "sudo systemctl is-active dnsmasq >/dev/null 2>&1"; then
        error_exit "DHCP server (dnsmasq) is not running"
    fi
    
    success "DHCP server is running"
}

# Generate test report
generate_report() {
    info "Generating test report..."
    
    local report_file="test-report-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$report_file" << EOF
# Proxmox VE on EC2 Test Report

**Test Date:** $(date)
**Instance Type:** $INSTANCE_TYPE
**Instance ID:** $INSTANCE_ID
**Public IP:** $PUBLIC_IP

## Access Information
- **Web Interface:** https://$PUBLIC_IP:8006/
- **Login:** root / $ROOT_PASSWORD
- **SSH:** \`ssh -i ${KEY_NAME}.pem admin@$PUBLIC_IP\`

## Test Results
✅ Prerequisites check passed
✅ EC2 instance launched successfully
✅ Cloud-init completed
✅ Proxmox packages installed
✅ Proxmox kernel active
✅ Web interface accessible
✅ Network configuration correct
✅ DHCP server running

## System Information
- **Kernel:** $(ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" "uname -r")
- **Proxmox Packages:** $(ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" admin@"$PUBLIC_IP" "dpkg -l | grep -c proxmox")

## Next Steps
1. Access web interface and create test containers/VMs
2. Test guest networking and DHCP
3. Upload ISOs and test VM creation

## Cleanup
To clean up resources:
\`\`\`bash
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
aws ec2 delete-key-pair --key-name $KEY_NAME
aws ec2 delete-security-group --group-id $SECURITY_GROUP_ID
rm -f ${KEY_NAME}.pem
\`\`\`
EOF
    
    success "Test report generated: $report_file"
}

# Main execution
main() {
    info "Starting Proxmox VE on EC2 deployment test..."
    info "Log file: $LOG_FILE"
    
    check_prerequisites
    
    local ami_id
    ami_id=$(get_debian_ami)
    
    create_key_pair
    create_security_group
    launch_instance "$ami_id"
    wait_for_instance
    wait_for_ssh
    wait_for_cloud_init
    set_root_password
    reboot_system
    test_proxmox_installation
    test_web_interface
    test_network_config
    generate_report
    
    success "🎉 All tests passed! Proxmox VE deployment successful!"
    info "Web Interface: https://$PUBLIC_IP:8006/"
    info "Login: root / $ROOT_PASSWORD"
    info "SSH: ssh -i ${KEY_NAME}.pem admin@$PUBLIC_IP"
    
    if [[ "${CLEANUP_AFTER_SUCCESS:-false}" == "true" ]]; then
        cleanup_resources
    else
        warning "Resources left running. Set CLEANUP_AFTER_SUCCESS=true to auto-cleanup."
    fi
}

# Handle script interruption
trap cleanup_resources EXIT INT TERM

# Run main function
main "$@"