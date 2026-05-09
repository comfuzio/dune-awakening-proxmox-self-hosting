````md
# 🤝 Contributing

Thank you for helping improve the **Dune: Awakening Proxmox Migration Guide**.

This project exists to help the community run the dedicated server natively on Proxmox with lower overhead, better stability, and fewer Windows dependencies.

---

# 🛠️ Ways to Contribute

## 📜 Alpine / Automation Scripts

If you have improvements for automating post-migration tasks such as:

- Network interface configuration
- Static IP setup
- k3s service recovery
- First-boot initialization

please submit a Pull Request.

---

## ⚡ Performance Optimization

Contributions related to performance tuning are welcome, including:

- CPU type and flags
- NUMA optimizations
- HugePages
- IO thread tuning
- VirtIO improvements
- Storage controller benchmarking

Please include:
- Your Proxmox version
- Hardware specifications
- Benchmark results or stability observations

---

## 🐞 Bug Reports

If a game update breaks compatibility or changes the migration workflow:

1. Open a GitHub Issue
2. Include logs and screenshots where possible
3. Describe:
   - What changed
   - Expected behavior
   - Actual behavior

Useful commands:

```bash
journalctl -xe
dmesg
kubectl get pods -A
