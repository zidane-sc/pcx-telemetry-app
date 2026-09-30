# 🏍️ PCX Telemetry App

Smart Telemetry & IoT Diagnostic Cluster for **Honda PCX 160** built with Flutter and PocketBase.

---

## ⚡ Features
- **Intelligent Fuel Model**: Speed-Density equation calculating real-time `km/L`, `L/h`, and Distance to Empty (DTE km).
- **Pre-Ride Inspection**: Standby battery meter, Cranking Voltage Dip test, and DTC fault code scanning.
- **Active Diagnostic Tests**: Radiator Fan Relay routine, Fuel Pump click test, and TPS potentiometer sweep.
- **Smart Maintenance Tracker**: Engine run hours and odometer countdown for engine oil, v-belt, roller, and coolant.
- **Offline-First Sync**: Auto-sync trips to PocketBase over Cloudflare Tunnel / Tailscale.
- **In-App Sentry Mini**: Automated crash and runtime error reporting to `app_logs` collection.

---

## 🛠️ Development & Running Locally

### On your laptop:
```bash
git clone https://github.com/zidane-sc/pcx-telemetry-app.git
cd pcx-telemetry-app
flutter pub get
flutter run
```

### GitHub Actions CI/CD:
Every push to `main` automatically triggers `.github/workflows/build-apk.yml`, running unit tests and generating `app-debug.apk` in the GitHub Actions Artifacts tab.
