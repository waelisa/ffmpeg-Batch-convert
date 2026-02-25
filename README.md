# Advanced AMD GPU Batch Video Converter

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.1.7-blue.svg)](#)
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

An advanced Bash script for high-performance batch video conversion leveraging AMD Advanced Media Framework (AMF) and VA-API. Designed specifically for AMD VGA owners to achieve professional-grade encoding with minimal CPU usage.

🚀 Features

    Universal AMD Support: Optimized presets for Polaris (RX 400/500), Vega, RDNA 1 (RX 5000), RDNA 2 (RX 6000), and RDNA 3 (RX 7000).

    AV1 Encoding: Full support for the latest AV1 codec on RDNA 3 / RX 7000 series hardware.

    Zero-Copy Pipeline: Performance-optimized hardware pipeline (Decode → Filter → Encode) that keeps data in GPU memory to eliminate system RAM bottlenecks.

    Smart B-Frame Management: Automatically detects your GPU architecture to apply safe B-frame settings, preventing crashes on older cards.

    HQVBR Technology: Utilizes High-Quality Variable Bitrate for consistent visual fidelity in high-motion scenes.

    Interactive UI: Built-in configuration menu using gum for easy, visual setup.

    Auto-Dependency: Detects your Linux distribution and installs required drivers and tools automatically.

📦 Installation

1. Download the script
```bash
wget https://github.com/waelisa/ffmpeg-Batch-convert/raw/refs/heads/main/ffmpeg-Batch-convert.sh
chmod +x ffmpeg-Batch-convert.sh
```
2. Install Dependencies

The script supports Ubuntu/Debian, Fedora, Arch, and openSUSE. Run this command to set up your environment:
```bash
sudo ./ffmpeg-Batch-convert.sh --install-deps
```
🛠 Usage
Basic Conversion

Automatically detects your AMD GPU and converts all supported files in the current folder to MP4:
```bash
./ffmpeg-Batch-convert.sh *.mkv
```
Interactive Menu (Recommended)

Launch the visual builder to select codecs, resolutions, and quality presets:
```bash
./ffmpeg-Batch-convert.sh --conf
```

Advanced Examples

Max Quality Archiving
```bash
./ffmpeg-Batch-convert.sh -p maxquality *.mp4
```
4K Streaming Optimization	
```bash
./ffmpeg-Batch-convert.sh -r 4K -p streaming *.mkv
```
AV1 (RX 7000 only)	
```bash
./ffmpeg-Batch-convert.sh -c av1 -p balanced *.mkv
```
Preserve Textures/Grain	
```bash
./ffmpeg-Batch-convert.sh --texture-preserve *.mov
```
Check GPU Architecture	./ffmpeg-Batch-convert.sh --gpu-info

📊 Quality Presets

Preset	Description	Tech Used

maxquality	Highest fidelity for archiving	CQP Mode, VBAQ, Pre-analysis

balanced	Best for general use	HQVBR, 15M Peak Bitrate

fast	Quick previews/transfers	Speed Priority, No Pre-analysis

highcompression	Smallest file sizes	VBR Latency Mode, Open GOP

streaming	Optimized for Plex/Jellyfin	Low Latency VBR, Gops_per_IDR: 60

📝 Hardware Architecture Notes

The script automatically adjusts to your hardware:

    Polaris (RX 400/500): Uses -bf 0 for maximum stability.

    Vega: Supports up to 2 B-frames.

    RDNA 1/2: Optimized for high-bitrate HEVC.

    RDNA 3: Unlocks AV1 and up to 5 B-frames.

👤 Author

Wael Isa

    Website: [wael.name](https://www.wael.name)

    GitHub: @waelisa

📜 License

This project is licensed under the MIT License. Use it, change it, share it.
---

## ☕ Support the Project

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg)](https://www.paypal.me/WaelIsa)
