# Proxmox VE on EC2 Test Suite

This test suite automates the deployment and validation of Proxmox VE on AWS EC2 instances.

## Quick Start

```bash
# Run the standard test
make test

# Or run directly
./run-test.sh
```

## Test Options

### Using Make (Recommended)
```bash
make test           # Standard test (c5.2xlarge)
make test-fast      # Faster test (c5.4xlarge)
make test-small     # Cheaper test (t3.small)
make test-cleanup   # Test with auto-cleanup
```

### Using Environment Variables
```bash
# Custom instance type
INSTANCE_TYPE=c5.xlarge ./run-test.sh

# Enable cleanup after success
CLEANUP_AFTER_SUCCESS=true ./run-test.sh

# Use different cloud-init file
CLOUD_INIT_FILE=my-custom-config.yaml ./run-test.sh
```

## Configuration

Edit `test-config.env` to customize default settings:

```bash
# Instance configuration
INSTANCE_TYPE=c5.2xlarge
VOLUME_SIZE=64

# Test behavior
CLEANUP_ON_FAILURE=true
CLEANUP_AFTER_SUCCESS=false

# Files
CLOUD_INIT_FILE=proxmox-on-ec2/cloud-init-modified.yaml
```

## What the Test Does

1. **Prerequisites Check**
   - Verifies AWS CLI is installed and configured
   - Checks that cloud-init file exists

2. **Resource Creation**
   - Creates SSH key pair
   - Creates security group with restricted access
   - Launches EC2 instance with cloud-init

3. **Deployment Validation**
   - Waits for instance to boot and SSH to be available
   - Monitors cloud-init completion
   - Sets root password for Proxmox web interface
   - Reboots to activate Proxmox kernel

4. **Functionality Testing**
   - Verifies Proxmox packages are installed
   - Confirms Proxmox kernel is active
   - Tests web interface accessibility
   - Validates network bridge configuration
   - Checks DHCP server status

5. **Reporting**
   - Generates detailed test report
   - Provides access credentials
   - Creates cleanup instructions

## Test Output

The test creates several files:
- `test-YYYYMMDD-HHMMSS.log` - Detailed execution log
- `test-report-YYYYMMDD-HHMMSS.md` - Test results and access info
- `proxmox-test-TIMESTAMP.pem` - SSH private key

## Cleanup

### Automatic Cleanup
```bash
# Clean up after successful test
CLEANUP_AFTER_SUCCESS=true ./run-test.sh

# Clean up on failure (default behavior)
CLEANUP_ON_FAILURE=true ./run-test.sh
```

### Manual Cleanup
```bash
# Clean up test artifacts
make clean

# Clean up AWS resources (get IDs from test report)
aws ec2 terminate-instances --instance-ids i-xxxxxxxxx
aws ec2 delete-key-pair --key-name proxmox-test-xxxxxxxxx
aws ec2 delete-security-group --group-id sg-xxxxxxxxx
```

## Troubleshooting

### Test Failures
1. Check the log file for detailed error messages
2. Verify AWS credentials and permissions
3. Ensure you have sufficient EC2 limits
4. Check the cloud-init file syntax

### Common Issues
- **SSH timeout**: Instance may be slow to boot, increase TEST_TIMEOUT
- **Cloud-init errors**: Check cloud-init.log on the instance
- **Web interface not accessible**: Verify security group rules
- **Proxmox not installed**: Check for package installation errors

### Debug Mode
```bash
# Enable verbose logging
set -x
./run-test.sh
```

## Customization

### Using Different Cloud-Init Files
```bash
# Test original config
CLOUD_INIT_FILE=proxmox-on-ec2/cloud-init.yaml ./run-test.sh

# Test custom config
CLOUD_INIT_FILE=my-custom-proxmox.yaml ./run-test.sh
```

### Testing Different Instance Types
```bash
# Test on metal instance (expensive!)
INSTANCE_TYPE=c5n.metal ./run-test.sh

# Test on smaller instance
INSTANCE_TYPE=t3.medium ./run-test.sh
```

### Custom Test Scenarios
Create your own test configuration:
```bash
cp test-config.env my-test.env
# Edit my-test.env
./run-test.sh my-test.env
```

## Integration with CI/CD

The test script returns appropriate exit codes and can be integrated into CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Test Proxmox Deployment
  run: |
    CLEANUP_AFTER_SUCCESS=true ./run-test.sh
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

## Cost Considerations

Approximate costs per test run:
- **t3.small**: ~$0.05 for 30 minutes
- **c5.2xlarge**: ~$0.20 for 30 minutes  
- **c5.4xlarge**: ~$0.40 for 30 minutes

Enable auto-cleanup to minimize costs:
```bash
CLEANUP_AFTER_SUCCESS=true ./run-test.sh
```