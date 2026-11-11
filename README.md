# PulseMatrix Pro

**PulseMatrix Pro** is a native Swift 6 & SwiftUI macOS hardware telemetry suite, Apple Silicon diagnostic monitor, Local AI / LLM inference profiler, and Menu Bar companion.

Built with a modern **Liquid Glass** aesthetic and a **Curated Card Bento Dashboard**, PulseMatrix Pro translates low-level Darwin Mach, `IOKit`, and `<libproc.h>` hardware telemetry into clear visual compositions and plain-English causal explanations.

---

## Key Capabilities

### 1. Liquid Glass Interface & Dual Footprint
- **Unified Behind-Window Liquid Glass (`NSVisualEffectView`)**: Full-window translucent canvas with adjustable **Glass Intensity (`15%–95%`)** so your desktop subtly bleeds through the interface.
- **Left-Side Module Menu Bar**: Integrated directly with the macOS window controls and live per-module telemetry badges (`All Modules`, `CPU`, `Memory`, `GPU & AI`, `Thermal`, `Battery`, `Disk & Net`, `Sessions & Health`).
- **Menu Bar Micro-UI & Floating PiP HUD**: Live Unicode sparklines (`▁▂▄▆█`), customizable status badges, a rich Menu Bar popover with 60-second Swift Charts sparklines, and an always-on-top Picture-in-Picture (`NSPanel`) hardware overlay with click-through support.

### 2. Curated Card Dashboard
- **Circular Gauges**: Overarching indicators for CPU %, Unified Memory %, Metal GPU %, SoC Peak °C, Battery Health %, and Compute Score.
- **Per-Core Apple Silicon Grids**: Visualizes individual **P-cores (Performance)** and **E-cores (Efficiency)** with distinct color-coding and single-core saturation detection.
- **Stacked Composition Bars**: Multi-segment breakdown bars for Unified Memory (`App`, `Wired`, `Compressed`, `Cached`, `Free`), CPU Load (`User`, `System`, `Idle`), GPU & AI Unified Memory Pool (`VRAM`, `AI Runtimes`, `Headroom to Wired Limit`), Thermal Power Domains, Battery Chemical Capacity, and APFS Storage.

### 3. Human-Centric Causal Insights Engine
- **Inline Plain-English Callouts**: Every hardware card includes an embedded explanation of what the numbers mean—highlighting single-core bottlenecks, VM swap thrashing, thermal throttling, or battery wear.

### 4. Local AI & LLM Inference Profiler
- **Automatic AI Runtime Detection**: Inspects process kernel arguments (`sysctl KERN_PROCARGS2`) to identify local inference servers (`llama-server`, `ollama`, `MLX`, `PyTorch`, `vLLM`, `LM Studio`, `whisper`).
- **Context Window & KV-Cache Inspector**: Detects `-c` / `--ctx-size` and `OLLAMA_CONTEXT_LENGTH` settings and flags oversized context windows that risk Unified Memory swap spillover.
- **Unified Memory Wired Limit Optimizer (`iogpu.wired_limit_mb`)**: Compares physical Unified Memory against Metal's default working-set cap and computes safe 85% / 90% GPU pinnable ceilings.

### 5. Workload Session Recorder, Health Reports & Prometheus Exporter
- **1-Second Resolution Session Recorder**: Record workload traces with A/B baseline comparison and **1%-Low Compute Stability** scoring; export to CSV and JSON.
- **5-Pillar Computer Health & Longevity Audit**: Generates an overall `0–100` grade across Thermal Headroom, Battery Longevity, Memory Sustainability, Storage Wear, and Compute Stability, with 1-click HTML and Markdown export.
- **Local Prometheus & JSON Server**: Optional HTTP exporter serving `/metrics` and `/api/v1/snapshot`.

---

## Configuration (`.env`)

All local environment settings, privacy masks, and optional API keys are loaded from `.env` (which is excluded via `.gitignore`).

1. Copy the template:
   ```bash
   cp .env.example .env
   ```
2. Configure `.env` as needed:
   - `PULSEMATRIX_ANONYMIZE_HOST="true"` — Masks your local hostname and macOS username in the UI and exported reports.
   - `PULSEMATRIX_PROMETHEUS_HOST="127.0.0.1"` / `PULSEMATRIX_PROMETHEUS_PORT="9101"` — Configures the local metrics server bind address and port.
   - `PULSEMATRIX_METRICS_API_KEY=""` — Optional Bearer token for `/metrics` and `/api/v1/snapshot`.

---

## Build, Test & Run

### Requirements
- macOS 14.0+ (Apple Silicon recommended)
- Swift 6.0+ / Xcode Command Line Tools

### Run Unit & Hardware Integration Tests
```bash
swift test
```

### Package & Launch `PulseMatrixPro.app`
```bash
zsh scripts/bundle_app.sh
open PulseMatrixPro.app
```

---

## License

Released under the [MIT License](LICENSE).
