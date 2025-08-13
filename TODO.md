# Proxmox Outpost Deployment - TODO

## ✅ Completed
- [x] Test Debian 12 with Proxmox VE 7 - **Working**
- [x] Test Debian 12 with Proxmox VE 8 - **Working** 
- [x] Fix SSL certificate generation for PVE 8
- [x] Add Ceph no-subscription repositories
- [x] Create comprehensive documentation (CLAUDE.md)
- [x] Update README with Quick Start guide

## 🚀 High Priority

### Metal Instance Optimization
- [ ] **Storage Configuration for c6id.metal**
  - Research optimal drive setup for c6id instances (NVMe SSD configuration)
  - Determine ZFS vs LVM setup for metal instances
  - Build automation for drive partitioning and filesystem setup
  
- [ ] **Networking for c6id.metal** 
  - Design multi-ENI configuration for metal instances
  - Plan IP allocation strategy for guest VMs
  - Create automation for SR-IOV and hardware passthrough setup

### Production Readiness
- [ ] **AMI Pipeline vs User Data Decision**
  - Evaluate pros/cons of pre-built AMI vs cloud-init approach
  - Consider maintenance overhead and update frequency
  - Test AMI creation from working Proxmox instances

## 🔧 Medium Priority

### Enhanced Automation
- [ ] **Automated Testing Suite**
  - Create test script with cleanup, logging, and error reporting
  - Add validation checks for successful Proxmox installation
  - Include Ceph installation testing
  - Generate deployment reports

- [ ] **Configuration Options**
  - Make hostname/FQDN configurable via parameters
  - Add support for custom network ranges
  - Allow custom Proxmox VE version selection
  - Support for different Debian versions

### Documentation & Examples
- [ ] **Add detailed comments** to cloud-init scripts explaining each step
- [ ] **Create example configurations** for different use cases
- [ ] **Add troubleshooting guide** with common issues and solutions
- [ ] **Performance tuning guide** for metal instances

## 🎯 Future Features

### Cluster Management
- [ ] **Multi-node cluster automation** (may be overkill for some use cases)
  - Automatic cluster initialization
  - Node joining automation
  - Shared storage configuration

### Advanced Features  
- [ ] **GPU passthrough setup** for metal instances
- [ ] **Backup automation** configuration
- [ ] **Monitoring integration** (Prometheus/Grafana)
- [ ] **Security hardening** scripts
- [ ] **Terraform modules** for infrastructure as code

### Cloud-Init Enhancements
- [ ] **PVE 7 specific version** for Debian 12 (force older Proxmox)
- [ ] **ARM64 support** for Graviton instances
- [ ] **Ubuntu support** (in addition to Debian)

## 📋 Research Items
- [ ] Cost comparison: metal vs virtualized instances for specific workloads
- [ ] Performance benchmarks: Proxmox on metal vs bare metal
- [ ] Security implications of running Proxmox in AWS
- [ ] Backup strategies for Proxmox VMs in AWS environment

---

## Notes
- Current working configurations: Debian 11+PVE7, Debian 12+PVE8
- SSL certificate issue resolved for PVE 8
- Ceph installation working with no-subscription repositories
- All automation tested on c5.4xlarge, needs validation on metal instances