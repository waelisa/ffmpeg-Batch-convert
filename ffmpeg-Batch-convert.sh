#!/usr/bin/env bash
#############################################################################################################################
#
# Advanced AMD GPU Batch Video Converter
# Wael Isa - www.wael.name
# GitHub: https://github.com/waelisa/ffmpeg-Batch-convert
# Version: 1.1.11
# Description: Batch convert video files using AMD GPU hardware acceleration
# Author: Based on AMD optimization guidelines
# License: MIT
#
# ============================================================================
# HOW TO USE
# ============================================================================
#
# BASIC CONVERSION (format auto-detected from the "to FORMAT" suffix):
#
#   ./ffmpeg-Batch-convert.sh video.webm to mp4
#   ./ffmpeg-Batch-convert.sh video.mp4 to webm
#   ./ffmpeg-Batch-convert.sh movie.mkv to mp4
#
# BATCH CONVERSION — CONVERT EVERY VIDEO IN THE CURRENT FOLDER:
#
#   ./ffmpeg-Batch-convert.sh all to mp4       <- recommended, shell-safe
#   ./ffmpeg-Batch-convert.sh --all to mp4     <- same, as a flag
#   ./ffmpeg-Batch-convert.sh * to mp4         <- also works, but relies
#                                                 on shell globbing
#
# The `all` keyword scans the current directory and picks every file
# whose extension is in the supported list below. Non-video files
# (this script, logs, configs, READMEs, subdirectories) are skipped.
#
# BATCH CONVERSION — SPECIFIC PATTERNS:
#
#   ./ffmpeg-Batch-convert.sh *.webm to mp4
#   ./ffmpeg-Batch-convert.sh *.mkv *.mp4 *.avi to mp4
#   ./ffmpeg-Batch-convert.sh "My Movie.webm" "Clip 2.mp4" to mkv
#
# WITH CODEC / PRESET OVERRIDES:
#
#   ./ffmpeg-Batch-convert.sh -c hevc -p maxquality all to mp4
#   ./ffmpeg-Batch-convert.sh -c h264 -p fast *.webm to mp4
#   ./ffmpeg-Batch-convert.sh -c hevc -q 20 --target-size 700M movie.mkv to mp4
#
# DRY RUN (print the ffmpeg command without executing):
#
#   ./ffmpeg-Batch-convert.sh --dry-run all to mp4
#
# CHECK YOUR SYSTEM (GPU, VA-API, dependencies):
#
#   ./ffmpeg-Batch-convert.sh --check-deps
#   ./ffmpeg-Batch-convert.sh --gpu-info
#
# INSTALL MISSING DEPENDENCIES (must be run with sudo):
#
#   sudo ./ffmpeg-Batch-convert.sh --install-deps
#
# INTERACTIVE MENU:
#
#   ./ffmpeg-Batch-convert.sh --conf
#
# FULL HELP:
#
#   ./ffmpeg-Batch-convert.sh --help
#
# ============================================================================
# FEATURES
# ============================================================================
#
#   - Universal AMD GPU support (Polaris, Vega, RDNA 1/2/3)
#   - Automatic dependency installation
#   - Multi-distribution support (apt, dnf, pacman, zypper)
#   - AMD GPU detection and VA-API/AMF support
#   - AV1 encoding support for RDNA 3
#   - Smart B-frame management per GPU architecture
#   - Zero-copy hardware pipeline (fixed VA-API)
#   - HQVBR for consistent quality
#   - Cross-format: webm→mp4, mp4→webm, mkv→mp4, and more
#   - Container-aware audio codec (aac / opus / vorbis / mp3)
#   - `all` keyword: convert every video in the current folder
#   - Wildcard-safe: `./script.sh * to mp4` skips non-video files
#   - Flexible output formats: to mp4, to mkv, to webm, to avi, ...
#   - Auto-detection from command line
#   - Fixed dry run output (no duplicate commands)
#   - Enhanced HEVC/VA-API compatibility
#   - Improved B-frame settings for RDNA 3
#
# ============================================================================
# CHANGELOG
# ============================================================================
#
#   v1.1.11 - FIXED critical batch bug: ((success_count++)) under `set -e`
#             returns non-zero when the counter was 0, aborting the script
#             right after the first file. Replaced with arithmetic
#             assignment `x=$((x + 1))` which always returns 0.
#           - Added `all` positional keyword (and `--all` flag): scans the
#             current directory for supported video files. Shell-glob safe.
#           - Fixed empty-array expansion under `set -u` (bash < 4.4).
#           - Renamed local `basename` variable that shadowed the command.
#           - Deduplicated the `*.$ext` fallback loop (vob / VOB collision).
#   v1.1.10 - Wildcard support: `./script.sh * to mp4` now works cleanly.
#           - Added "HOW TO USE" section to the header.
#           - Non-video files are silently skipped when a glob is expanded.
#           - Added --no-filter to disable input extension filtering.
#   v1.1.9 - Cross-format conversion overhaul:
#           - Added AUDIO_CODECS map (aac/opus/vorbis/mp3 per container)
#           - Replaced fragile "eval set --" arg parsing with array-based
#             parsing (fixes filenames with spaces / special characters)
#           - Removed detect_output_format_from_args / remove_to_args
#           - Fixed VAAPI presets: removed invalid -quality/-compression_level
#             options that caused h264_vaapi to abort immediately
#           - AMF path no longer forces VA-API decode (fixes webm/mp4 input)
#           - Guarded -map_metadata for containers that reject it (webm/ogv)
#           - Added stream mapping for mp4/m4v/mov to drop unsupported streams
#           - Optional VA-API hardware decode for h264/hevc input
#           - VP9/Theora remain CPU-encoded as before
#   v1.1.8 - Fixed dry run output duplication
#           - Enhanced HEVC VA-API compatibility
#           - Improved B-frame settings for RDNA 3
#           - Added codec override when format changes
#           - Better handling of -c flag with to syntax
#   v1.1.7 - Fixed log output redirection to stderr
#   v1.1.6 - Fixed VA-API command construction, added bc dependency
#   v1.1.5 - Added "to [format]" syntax support
#   v1.1.4 - Fixed VOB file duration issues, added DVD preset
#   v1.1.3 - Fixed VOB file duration parsing
#   v1.1.2 - Fixed unbound variable errors
#   v1.1.1 - Added universal AMD GPU support, AV1 encoding
#   v1.1.0 - Added interactive menu, configuration files
#
#############################################################################################################################

set -euo pipefail
IFS=$'\n\t'

# Script configuration
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
VERSION="1.1.11"
LOG_FILE="${SCRIPT_DIR}/conversion_$(date +%Y%m%d_%H%M%S).log"
OUTPUT_DIR="output"
CONFIG_FILE="${SCRIPT_DIR}/ffmpeg-Batch-convert.conf"
PROFILES_DIR="${SCRIPT_DIR}/profiles"

# ANSI color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
WHITE="\033[1;37m"
BOLD="\033[1m"
NC="\033[0m" # No Color

# Default settings
DEFAULT_CODEC="h264"
DEFAULT_QUALITY="balanced"
DEFAULT_AUDIO_BITRATE="128k"
DEFAULT_CONTAINER="mp4"
INPUT_EXTENSIONS=("mov" "mkv" "avi" "flv" "m2ts" "ts" "mp4" "webm" "wmv" "m4v" "3gp" "ogv" "mpeg" "mpg" "vob")

# Required dependencies
REQUIRED_COMMANDS=("ffmpeg" "vainfo" "lspci" "bc" "ffprobe")
REQUIRED_PACKAGES=("ffmpeg" "vainfo" "pciutils" "bc" "ffmpeg")

# Supported output formats and their default codecs
declare -A OUTPUT_FORMATS=(
    ["mp4"]="h264"
    ["mkv"]="h264"
    ["avi"]="h264"
    ["mov"]="h264"
    ["webm"]="vp9"
    ["m4v"]="h264"
    ["3gp"]="h264"
    ["ogv"]="theora"
)

# Audio codec per output container
declare -A AUDIO_CODECS=(
    ["mp4"]="aac"
    ["m4v"]="aac"
    ["mkv"]="aac"
    ["mov"]="aac"
    ["avi"]="libmp3lame"
    ["webm"]="libopus"
    ["ogv"]="libvorbis"
    ["3gp"]="aac"
)

# Format compatibility with codecs
declare -A FORMAT_COMPATIBILITY=(
    ["mp4"]="h264 hevc av1"
    ["mkv"]="h264 hevc av1 vp9 theora"
    ["avi"]="h264"
    ["mov"]="h264 hevc"
    ["webm"]="vp9 av1"
    ["m4v"]="h264 hevc"
    ["3gp"]="h264"
    ["ogv"]="theora"
)

# Initialize variables with defaults
DEBUG="${DEBUG:-false}"
DRY_RUN="${DRY_RUN:-false}"
NO_HWACCEL="${NO_HWACCEL:-false}"
FORCE="${FORCE:-false}"
KEEP_TREE="${KEEP_TREE:-false}"
NO_VBAQ="${NO_VBAQ:-false}"
NO_PREANALYSIS="${NO_PREANALYSIS:-false}"
NO_OPENGOP="${NO_OPENGOP:-false}"
TEXTURE_PRESERVE="${TEXTURE_PRESERVE:-false}"
USE_AMF="${USE_AMF:-false}"
HAS_VAAPI="${HAS_VAAPI:-false}"
HAS_AMF="${HAS_AMF:-false}"
HAS_HEVC_HW="${HAS_HEVC_HW:-false}"
HAS_AV1_HW="${HAS_AV1_HW:-false}"
HAS_OPEN_GOP="${HAS_OPEN_GOP:-false}"
GPU_ARCHITECTURE="${GPU_ARCHITECTURE:-UNKNOWN}"
RENDER_DEVICE="${RENDER_DEVICE:-}"
FORCE_PROCESS="${FORCE_PROCESS:-false}"
NO_FILTER="${NO_FILTER:-false}"

# Resolution presets
declare -A RESOLUTION_PRESETS=(
    ["480p"]="854x480"
    ["720p"]="1280x720"
    ["1080p"]="1920x1080"
    ["2K"]="2560x1440"
    ["4K"]="3840x2160"
    ["8K"]="7680x4320"
)

# GPU Architecture detection
declare -A AMD_ARCHITECTURES=(
    ["POLARIS"]="400 500 400X 500X"
    ["VEGA"]="Vega 56 Vega 64 Radeon VII"
    ["RDNA1"]="5500 5600 5700"
    ["RDNA2"]="6400 6500 6600 6700 6800 6900"
    ["RDNA3"]="7600 7700 7800 7900"
)

# ============================================
# Enhanced AMD-Specific Encoding Presets v6
# ============================================

declare -A QUALITY_PRESETS=(
    ["maxquality"]="-quality quality -rc cqp -qp_i 18 -qp_p 18 -qp_b 22 -vbaq 1 -preanalysis 1 -me full -maxaufsize 4 -gops_per_idr 60 -open_gop 1 -luma_adaptive_quantization 1"
    ["balanced"]="-quality quality -rc hqvbr -qvbr_quality_level 22 -maxrate 15M -peak_bitrate 15M -bufsize 24M -vbaq 1 -preanalysis 1 -me quarter -maxaufsize 3 -gops_per_idr 30 -open_gop 1"
    ["fast"]="-quality speed -rc vbr_peak -maxrate 8M -bufsize 16M -vbaq 0 -preanalysis 0 -me half -maxaufsize 2 -gops_per_idr 15"
    ["highcompression"]="-quality quality -rc vbr_latency -qvbr_quality_level 26 -maxrate 8M -bufsize 16M -vbaq 1 -preanalysis 1 -me full -maxaufsize 4 -gops_per_idr 45 -open_gop 1"
    ["streaming"]="-quality quality -rc vbr_latency -qvbr_quality_level 23 -maxrate 10M -bufsize 20M -vbaq 1 -preanalysis 1 -me quarter -maxaufsize 3 -gops_per_idr 60 -open_gop 1"
    ["dvd"]="-quality quality -rc hqvbr -qvbr_quality_level 22 -maxrate 8M -bufsize 16M -vbaq 1 -preanalysis 1 -me quarter -maxaufsize 3 -gops_per_idr 30 -open_gop 1"
)

# VA-API presets — only universally accepted options.
# -quality / -compression_level are NOT valid on most builds and cause
# h264_vaapi to abort immediately. B-frames/refs come from the arch helper.
declare -A VAAPI_QUALITY_PRESETS=(
    ["maxquality"]="-rc_mode CQP -qp 18"
    ["balanced"]="-rc_mode VBR -b:v 8M -maxrate 15M -qp 22"
    ["fast"]="-rc_mode VBR -b:v 5M -maxrate 8M"
    ["highcompression"]="-rc_mode VBR -b:v 3M -maxrate 5M -qp 26"
    ["streaming"]="-rc_mode VBR -b:v 8M -maxrate 10M -qp 23"
    ["dvd"]="-rc_mode VBR -b:v 4M -maxrate 8M -qp 22"
)

declare -A AV1_QUALITY_PRESETS=(
    ["maxquality"]="-quality quality -rc cqp -qp 18 -vbaq 1 -preanalysis 1"
    ["balanced"]="-quality quality -rc hqvbr -qvbr_quality_level 22 -maxrate 12M"
    ["fast"]="-quality speed -rc vbr_peak -maxrate 8M"
    ["highcompression"]="-quality quality -rc vbr_latency -qvbr_quality_level 26 -maxrate 6M"
    ["streaming"]="-quality quality -rc vbr_latency -qvbr_quality_level 23 -maxrate 8M"
    ["dvd"]="-quality quality -rc hqvbr -qvbr_quality_level 22 -maxrate 6M"
)

declare -A BFRAME_SAFETY=(
    ["POLARIS"]="-bf 0"
    ["VEGA"]="-bf 2 -refs 3"
    ["RDNA1"]="-bf 3 -refs 4"
    ["RDNA2"]="-bf 4 -refs 5"
    ["RDNA3"]="-bf 4 -refs 5"
    ["UNKNOWN"]="-bf 2 -refs 3"
)

declare -A BFRAME_SETTINGS=(
    ["h264"]="-bf 3 -refs 6 -b_strategy 2 -weightb 1 -directpred 3 -b_pyramid normal"
    ["hevc"]="-bf 4 -refs 5 -b_strategy 2 -weightb 1 -b_pyramid 1"
    ["av1"]="-bf 3 -refs 4"
    ["vp9"]=""
    ["theora"]=""
)

declare -A ME_SETTINGS=(
    ["maxquality"]="-me_method full -subq 7 -trellis 2 -cmp 2 -mbd 2 -flags +mv0 -flags2 +fastpskip"
    ["balanced"]="-me_method hex -subq 5 -trellis 1 -cmp 1 -mbd 1"
    ["fast"]="-me_method dia -subq 2 -trellis 0 -cmp 0 -mbd 0"
    ["highcompression"]="-me_method full -subq 6 -trellis 2 -cmp 2 -mbd 2"
    ["streaming"]="-me_method hex -subq 5 -trellis 1 -cmp 1 -mbd 1"
    ["dvd"]="-me_method hex -subq 5 -trellis 1 -cmp 1 -mbd 1"
)

declare -A TEXTURE_SETTINGS=(
    ["preserve"]="-vbaq 1 -preanalysis 1 -qcomp 0.8 -psy-rd 1.0 -luma_adaptive_quantization 1"
    ["balanced"]="-vbaq 1 -preanalysis 1 -qcomp 0.7 -psy-rd 0.8"
    ["fast"]="-vbaq 0 -preanalysis 0 -qcomp 0.6"
)

# ============================================
# Utility Functions
# ============================================

print_banner() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${CYAN}║                                                                   ║${NC}" >&2
    echo -e "${CYAN}║   Advanced AMD GPU Batch Video Converter v${VERSION}                   ║${NC}" >&2
    echo -e "${CYAN}║   Wael Isa - www.wael.name                                        ║${NC}" >&2
    echo -e "${CYAN}║   GitHub: https://github.com/waelisa/ffmpeg-Batch-convert         ║${NC}" >&2
    echo -e "${CYAN}║                                                                   ║${NC}" >&2
    echo -e "${CYAN}║   Universal AMD GPU Support:                                       ║${NC}" >&2
    echo -e "${CYAN}║   • Polaris (RX 400/500) • Vega • RDNA 1 • RDNA 2 • RDNA 3        ║${NC}" >&2
    echo -e "${CYAN}║   • AV1 Encoding for RX 7000 series                                ║${NC}" >&2
    echo -e "${CYAN}║   • Smart B-frame per architecture                                 ║${NC}" >&2
    echo -e "${CYAN}║   • Zero-copy hardware pipeline                                    ║${NC}" >&2
    echo -e "${CYAN}║   • Cross-format: webm→mp4, mp4→webm, mkv→mp4, and more            ║${NC}" >&2
    echo -e "${CYAN}║   • Batch:   ./ffmpeg-Batch-convert.sh all to mp4                  ║${NC}" >&2
    echo -e "${CYAN}║   • Flexible output formats: to mp4, to mkv, to webm, to avi       ║${NC}" >&2
    echo -e "${CYAN}║   • Auto-detection from command line                               ║${NC}" >&2
    echo -e "${CYAN}║   • Fixed dry run output (no duplicates)                           ║${NC}" >&2
    echo -e "${CYAN}║   • Enhanced HEVC VA-API compatibility                             ║${NC}" >&2
    echo -e "${CYAN}║                                                                   ║${NC}" >&2
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}" >&2
}

print_usage() {
    echo -e "${GREEN}USAGE:${NC}" >&2
    echo -e "    $SCRIPT_NAME [OPTIONS] [FILES... | all] [to FORMAT]" >&2
    echo >&2
    echo -e "${GREEN}OPTIONS:${NC}" >&2
    echo -e "    -h, --help              Show this help message" >&2
    echo -e "    -v, --version           Show version information" >&2
    echo -e "    -d, --debug             Enable debug output" >&2
    echo -e "    --dry-run              Show commands without executing" >&2
    echo -e "    --check-deps           Check if all dependencies are installed" >&2
    echo -e "    --install-deps         Install required dependencies (run as root)" >&2
    echo -e "    --conf                 Interactive configuration menu" >&2
    echo -e "    --save-conf NAME       Save current settings as profile" >&2
    echo -e "    --load-conf NAME       Load profile" >&2
    echo -e "    --list-conf            List available profiles" >&2
    echo -e "    --gpu-info             Display detailed GPU information" >&2
    echo -e "    --force-process        Force processing even with malformed files" >&2
    echo -e "    --no-filter            Do not filter input files by extension" >&2
    echo >&2
    echo -e "${YELLOW}Input Keywords:${NC}" >&2
    echo -e "    all                     Convert every supported video file in the" >&2
    echo -e "                            current directory. Shell-glob safe. Same as" >&2
    echo -e "                            --all, or './script.sh * to FORMAT'." >&2
    echo >&2
    echo -e "${YELLOW}Output Options:${NC}" >&2
    echo -e "    -o, --output DIR        Output directory (default: ./output)" >&2
    echo -e "    -c, --codec CODEC       Video codec: h264, hevc, av1, vp9, theora" >&2
    echo -e "                            (default: auto-detected from format)" >&2
    echo -e "    -p, --preset PRESET     Quality preset: " >&2
    echo -e "                            • maxquality - Maximum quality (largest files)" >&2
    echo -e "                            • balanced  - Good quality/size balance" >&2
    echo -e "                            • fast      - Fastest encoding" >&2
    echo -e "                            • highcompression - Smallest files" >&2
    echo -e "                            • streaming - Optimized for media servers" >&2
    echo -e "                            • dvd       - Optimized for DVD/VOB files" >&2
    echo -e "                            (default: balanced)" >&2
    echo -e "    -q, --quality VAL       Quality override (16-32, lower = better)" >&2
    echo -e "    -a, --audio-bitrate R   Audio bitrate (default: 128k)" >&2
    echo -e "    -f, --format EXT        Output container (default: mp4)" >&2
    echo -e "    -r, --resolution PRESET Resolution preset: 480p, 720p, 1080p, 2K, 4K, 8K" >&2
    echo >&2
    echo -e "${YELLOW}Output Format Shortcuts:${NC}" >&2
    echo -e "    to mp4                  Convert to MP4 format" >&2
    echo -e "    to mkv                  Convert to MKV format" >&2
    echo -e "    to avi                  Convert to AVI format" >&2
    echo -e "    to webm                 Convert to WebM format" >&2
    echo -e "    to mov                  Convert to MOV format" >&2
    echo -e "    to m4v                  Convert to M4V format" >&2
    echo -e "    to 3gp                  Convert to 3GP format" >&2
    echo -e "    to ogv                  Convert to OGV format" >&2
    echo >&2
    echo -e "${YELLOW}Processing Options:${NC}" >&2
    echo -e "    --keep-tree             Preserve directory structure" >&2
    echo -e "    --no-hwaccel            Disable hardware acceleration (CPU only)" >&2
    echo -e "    --force                 Overwrite existing files" >&2
    echo -e "    --no-vbaq               Disable Variance Based Adaptive Quantization" >&2
    echo -e "    --no-preanalysis        Disable pre-analysis (faster but lower quality)" >&2
    echo -e "    --no-opengop            Disable Open GOP (better compatibility)" >&2
    echo -e "    --texture-preserve      Maximum texture detail preservation" >&2
    echo -e "    --target-size SIZE      Target file size (e.g., 100M, 1G)" >&2
    echo >&2
    echo -e "${YELLOW}Filter Options:${NC}" >&2
    echo -e "    --scale WxH             Scale video (e.g., 1920x1080, -1x720 for height 720)" >&2
    echo -e "    --fps FPS               Set output framerate" >&2
    echo -e "    --trim START:DURATION   Trim video (e.g., 00:01:00:30 for 1m30s)" >&2
    echo -e "    --deinterlace           Force deinterlacing (auto-enabled for VOB)" >&2
    echo -e "    --denoise LEVEL         Apply denoising (low, medium, high)" >&2
    echo -e "    --crop W:H:X:Y          Crop video (width:height:x:y)" >&2
    echo >&2
    echo -e "${GREEN}EXAMPLES:${NC}" >&2
    echo -e "    # Check dependencies first" >&2
    echo -e "    $SCRIPT_NAME --check-deps" >&2
    echo >&2
    echo -e "    # Install missing dependencies (requires sudo)" >&2
    echo -e "    sudo $SCRIPT_NAME --install-deps" >&2
    echo >&2
    echo -e "    # Convert ONE WebM to MP4 (VP9/Opus -> H.264/AAC)" >&2
    echo -e "    $SCRIPT_NAME video.webm to mp4" >&2
    echo >&2
    echo -e "    # Convert EVERY video in the current folder to mp4" >&2
    echo -e "    $SCRIPT_NAME all to mp4" >&2
    echo >&2
    echo -e "    # Same, but only webm files (shell-globbed)" >&2
    echo -e "    $SCRIPT_NAME *.webm to mp4" >&2
    echo >&2
    echo -e "    # Batch with a codec/preset override" >&2
    echo -e "    $SCRIPT_NAME -c hevc -p maxquality all to mp4" >&2
    echo >&2
    echo -e "    # Dry run (shows the ffmpeg command for every file)" >&2
    echo -e "    $SCRIPT_NAME --dry-run all to mp4" >&2
    echo >&2
    echo -e "    # Convert VOB files to AVI with quality preset" >&2
    echo -e "    $SCRIPT_NAME --force-process -p dvd all to avi" >&2
    echo >&2
    echo -e "${CYAN}AMD GPU ARCHITECTURE NOTES:${NC}" >&2
    echo -e "    • Polaris (RX 400/500): Limited B-frames, use -bf 0 for stability" >&2
    echo -e "    • Vega: Good B-frame support up to 2" >&2
    echo -e "    • RDNA 1 (RX 5000): Full B-frame support up to 3" >&2
    echo -e "    • RDNA 2 (RX 6000): Enhanced B-frame support up to 4" >&2
    echo -e "    • RDNA 3 (RX 7000): AV1 encoding, B-frame support up to 4 for HEVC" >&2
    echo >&2
    echo -e "${BLUE}Supported input formats:${NC} ${INPUT_EXTENSIONS[*]}" >&2
    echo -e "${BLUE}Supported output formats:${NC} ${!OUTPUT_FORMATS[*]}" >&2
}

print_version() {
    echo "Advanced AMD GPU Batch Video Converter v${VERSION}" >&2
    echo "Wael Isa - www.wael.name" >&2
    echo "GitHub: https://github.com/waelisa/ffmpeg-Batch-convert" >&2
    echo "Universal AMD GPU Support (Polaris → RDNA 3)" >&2
}

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")    echo -e "${GREEN}[INFO]${NC} $message" >&2 ;;
        "WARN")    echo -e "${YELLOW}[WARN]${NC} $message" >&2 ;;
        "ERROR")   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        "DEBUG")   [[ "${DEBUG:-false}" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $message" >&2 ;;
        "AMD")     echo -e "${CYAN}[AMD]${NC} $message" >&2 ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" >&2 ;;
        *)         echo "$message" >&2 ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# Returns 0 if the file extension is one of INPUT_EXTENSIONS (case-insensitive)
is_supported_input_file() {
    local filename="$1"

    # Must be a regular file
    [[ -f "$filename" ]] || return 1

    # Extract extension (from the last dot)
    local ext="${filename##*.}"
    if [[ "$ext" == "$filename" || -z "$ext" ]]; then
        # No extension
        return 1
    fi
    ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')

    local supported
    for supported in "${INPUT_EXTENSIONS[@]}"; do
        local sup_lower
        sup_lower=$(printf '%s' "$supported" | tr '[:upper:]' '[:lower:]')
        if [[ "$sup_lower" == "$ext" ]]; then
            return 0
        fi
    done
    return 1
}

# Echo every supported video file in the current directory (one per line).
# Used by the `all` keyword. Skips the script itself, its log, and its
# output directory.
collect_all_videos_in_cwd() {
    local f
    for f in *; do
        [[ -e "$f" ]] || continue
        [[ -d "$f" ]] && continue
        [[ "$f" == "$SCRIPT_NAME" ]] && continue
        if is_supported_input_file "$f"; then
            printf '%s\n' "$f"
        fi
    done
}

# ============================================
# Dependency Checking & Installation
# ============================================

check_dependencies() {
    local missing=()
    local available=()

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${CYAN}║                    Dependency Check                               ║${NC}" >&2
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}" >&2

    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if check_command "$cmd"; then
            available+=("$cmd")
            echo -e "  ${GREEN}✓${NC} $cmd: ${GREEN}Installed${NC}" >&2
        else
            missing+=("$cmd")
            echo -e "  ${RED}✗${NC} $cmd: ${RED}Missing${NC}" >&2
        fi
    done

    echo >&2
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo -e "${GREEN}All dependencies are installed!${NC}" >&2
        return 0
    else
        echo -e "${YELLOW}Missing dependencies: ${missing[*]}${NC}" >&2
        echo -e "${YELLOW}Run 'sudo $SCRIPT_NAME --install-deps' to install missing dependencies${NC}" >&2
        return 1
    fi
}

detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/fedora-release ]]; then
        echo "fedora"
    elif [[ -f /etc/arch-release ]]; then
        echo "arch"
    elif [[ -f /etc/SuSE-release ]]; then
        echo "suse"
    else
        echo "unknown"
    fi
}

get_package_manager() {
    local distro="$1"
    case "$distro" in
        ubuntu|debian|linuxmint|popos)  echo "apt" ;;
        fedora|rhel|centos|almalinux|rocky) echo "dnf" ;;
        arch|manjaro|endeavouros)       echo "pacman" ;;
        opensuse*|suse)                 echo "zypper" ;;
        *)                              echo "unknown" ;;
    esac
}

get_install_command() {
    local distro="$1"
    local pkg_manager="$2"
    local package="$3"

    case "$pkg_manager" in
        apt)     echo "apt install -y $package" ;;
        dnf)     echo "dnf install -y $package" ;;
        pacman)  echo "pacman -S --noconfirm $package" ;;
        zypper)  echo "zypper install -y $package" ;;
        *)       echo "" ;;
    esac
}

install_dependencies() {
    log "INFO" "Checking and installing dependencies..."

    local missing_deps=()
    local missing_packages=()

    for i in "${!REQUIRED_COMMANDS[@]}"; do
        local cmd="${REQUIRED_COMMANDS[$i]}"
        local pkg="${REQUIRED_PACKAGES[$i]}"

        if ! check_command "$cmd"; then
            missing_deps+=("$cmd")
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        log "INFO" "All dependencies are already installed."
        return 0
    fi

    log "INFO" "Missing dependencies: ${missing_deps[*]}"

    local distro=$(detect_distribution)
    local pkg_manager=$(get_package_manager "$distro")

    log "INFO" "Detected distribution: $distro"
    log "INFO" "Using package manager: $pkg_manager"

    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Dependencies need to be installed, but script is not running as root."
        log "ERROR" "Please run: sudo $SCRIPT_NAME --install-deps"

        echo -e "\n${YELLOW}Manual installation commands for your distribution:${NC}" >&2
        for pkg in "${missing_packages[@]}"; do
            local install_cmd=$(get_install_command "$distro" "$pkg_manager" "$pkg")
            if [[ -n "$install_cmd" ]]; then
                echo -e "  sudo $install_cmd" >&2
            fi
        done
        return 1
    fi

    case "$pkg_manager" in
        apt)
            log "INFO" "Updating package lists..."
            apt update
            log "INFO" "Installing packages: ${missing_packages[*]}"
            apt install -y "${missing_packages[@]}" mesa-va-drivers \
                libva-drm2 libva-x11-2 va-driver-all \
                mesa-utils wget
            ;;

        dnf)
            log "INFO" "Installing packages: ${missing_packages[*]}"
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                dnf install -y https://download1.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm
            fi
            dnf install -y "${missing_packages[@]}" mesa-va-drivers \
                libva-utils
            ;;

        pacman)
            log "INFO" "Installing packages: ${missing_packages[*]}"
            pacman -S --noconfirm "${missing_packages[@]}" libva-mesa-driver \
                libva-utils
            ;;

        zypper)
            log "INFO" "Installing packages: ${missing_packages[*]}"
            zypper install -y "${missing_packages[@]}" Mesa-dri \
                libva-utils
            ;;

        *)
            log "ERROR" "Unsupported distribution for automatic installation"
            echo -e "\n${YELLOW}Please install manually:${NC}" >&2
            echo "  ffmpeg, vainfo, pciutils, bc" >&2
            return 1
            ;;
    esac

    local still_missing=()
    for cmd in "${missing_deps[@]}"; do
        if ! check_command "$cmd"; then
            still_missing+=("$cmd")
        fi
    done

    if [[ ${#still_missing[@]} -eq 0 ]]; then
        log "SUCCESS" "All dependencies installed successfully!"
    else
        log "ERROR" "Failed to install: ${still_missing[*]}"
        return 1
    fi

    if ! check_command "gum"; then
        install_gum
    fi

    log "INFO" "Dependencies installation completed."
}

# ============================================
# Gum Installation & Menu Functions
# ============================================

install_gum() {
    log "INFO" "Installing gum for interactive menus..."

    local distro=$(detect_distribution)
    local pkg_manager=$(get_package_manager "$distro")

    if [[ $EUID -ne 0 ]]; then
        log "WARN" "Need root to install gum. Please run: sudo $0 --install-deps"
        return 1
    fi

    case "$pkg_manager" in
        apt)
            local temp_dir=$(mktemp -d)
            cd "$temp_dir"
            wget -q "https://github.com/charmbracelet/gum/releases/download/v0.14.0/gum_0.14.0_amd64.deb"
            dpkg -i gum_0.14.0_amd64.deb
            apt-get install -f -y
            cd - > /dev/null
            rm -rf "$temp_dir"
            ;;
        dnf)
            echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | tee /etc/yum.repos.d/charm.repo
            dnf install -y gum
            ;;
        pacman)
            pacman -S --noconfirm gum
            ;;
        zypper)
            zypper install -y gum
            ;;
        *)
            log "INFO" "Downloading gum binary directly..."
            local temp_dir=$(mktemp -d)
            cd "$temp_dir"
            wget -q "https://github.com/charmbracelet/gum/releases/download/v0.14.0/gum_0.14.0_Linux_x86_64.tar.gz"
            tar -xzf gum_*.tar.gz
            cp gum_*/gum /usr/local/bin/
            chmod +x /usr/local/bin/gum
            cd - > /dev/null
            rm -rf "$temp_dir"
            ;;
    esac

    if check_command "gum"; then
        log "SUCCESS" "gum installed successfully"
        return 0
    else
        log "ERROR" "Failed to install gum"
        return 1
    fi
}

ensure_gum() {
    if ! check_command "gum"; then
        log "INFO" "gum not found. Installing for interactive menu..."
        install_gum
    fi
}

interactive_menu() {
    ensure_gum

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${CYAN}║              Interactive Configuration Builder                     ║${NC}" >&2
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}" >&2

    if ! check_dependencies; then
        if gum confirm "Missing dependencies. Install them now?"; then
            install_dependencies
        else
            log "ERROR" "Cannot continue without dependencies"
            exit 1
        fi
    fi

    detect_hardware_capabilities

    local format_options=(${!OUTPUT_FORMATS[@]})
    CONTAINER=$(gum choose --header "Select output format" "${format_options[@]}" --selected "mp4")

    local compatible_codecs=(${FORMAT_COMPATIBILITY[$CONTAINER]})
    CODEC=$(gum choose --header "Select video codec" "${compatible_codecs[@]}" --selected "${OUTPUT_FORMATS[$CONTAINER]}")

    PRESET=$(gum choose --header "Select quality preset" \
        "maxquality" "balanced" "fast" "highcompression" "streaming" "dvd" --selected "balanced")

    if gum confirm "Apply resolution preset?" --default=false; then
        local res=$(gum choose --header "Select resolution" \
            "480p" "720p" "1080p" "2K" "4K" "8K")
        SCALE="${RESOLUTION_PRESETS[$res]}"
    fi

    if gum confirm "Custom quality value?" --default=false; then
        QUALITY_VAL=$(gum input --placeholder "Enter quality value (16-32, lower=better)" --value "22")
    fi

    AUDIO_BITRATE=$(gum input --placeholder "Audio bitrate (e.g., 128k)" --value "128k")

    if gum confirm "Configure advanced options?" --default=false; then
        echo -e "${YELLOW}Advanced Options:${NC}" >&2

        if gum confirm "Enable VBAQ? (better texture detail)" --default=true; then
            NO_VBAQ="false"
        else
            NO_VBAQ="true"
        fi

        if gum confirm "Enable pre-analysis? (better quality)" --default=true; then
            NO_PREANALYSIS="false"
        else
            NO_PREANALYSIS="true"
        fi

        if gum confirm "Enable Open GOP? (better compression)" --default=true; then
            NO_OPENGOP="false"
        else
            NO_OPENGOP="true"
        fi

        if gum confirm "Enable texture preservation? (better detail)" --default=false; then
            TEXTURE_PRESERVE="true"
        fi

        if gum confirm "Force processing for malformed files?" --default=false; then
            FORCE_PROCESS="true"
        fi

        if gum confirm "Target specific file size?" --default=false; then
            TARGET_SIZE=$(gum input --placeholder "Target size (e.g., 100M, 1G)")
        fi
    fi

    if gum confirm "Apply video filters?" --default=false; then
        if gum confirm "Deinterlace?" --default=false; then
            DEINTERLACE="true"
        fi

        if gum confirm "Apply denoising?" --default=false; then
            DENOISE=$(gum choose --header "Denoise level" "low" "medium" "high")
        fi

        if gum confirm "Set framerate?" --default=false; then
            FPS=$(gum input --placeholder "Framerate (e.g., 30, 60)")
        fi

        if gum confirm "Crop video?" --default=false; then
            CROP=$(gum input --placeholder "Crop (width:height:x:y) e.g., 1920:1080:0:0")
        fi
    fi

    OUTPUT_DIR=$(gum input --placeholder "Output directory" --value "output")

    if gum confirm "Save this configuration as a profile?" --default=false; then
        local profile_name=$(gum input --placeholder "Profile name")
        save_configuration "$profile_name"
    fi

    echo -e "\n${GREEN}Configuration Summary:${NC}" >&2
    echo -e "  Format: $CONTAINER" >&2
    echo -e "  Codec: $CODEC" >&2
    echo -e "  Preset: $PRESET" >&2
    [[ -n "${SCALE:-}" ]] && echo -e "  Resolution: $SCALE" >&2
    [[ -n "${QUALITY_VAL:-}" ]] && echo -e "  Quality: $QUALITY_VAL" >&2
    echo -e "  Audio: $AUDIO_BITRATE" >&2
    [[ "${NO_VBAQ:-false}" == "true" ]] && echo -e "  VBAQ: Disabled" >&2 || echo -e "  VBAQ: Enabled" >&2
    [[ "${NO_PREANALYSIS:-false}" == "true" ]] && echo -e "  Pre-analysis: Disabled" >&2 || echo -e "  Pre-analysis: Enabled" >&2
    [[ "${NO_OPENGOP:-false}" == "true" ]] && echo -e "  Open GOP: Disabled" >&2 || echo -e "  Open GOP: Enabled" >&2
    [[ "${TEXTURE_PRESERVE:-false}" == "true" ]] && echo -e "  Texture Preservation: Enabled" >&2
    [[ "${FORCE_PROCESS:-false}" == "true" ]] && echo -e "  Force Processing: Enabled" >&2

    if gum confirm "Start conversion with these settings?" --default=true; then
        local files=()
        while IFS= read -r file; do
            files+=("$file")
        done < <(gum file --directory . --file --all)

        if [[ ${#files[@]} -gt 0 ]]; then
            process_files "${files[@]}"
        else
            log "ERROR" "No files selected"
        fi
    fi
}

# ============================================
# Configuration File Management
# ============================================

save_configuration() {
    local profile_name="${1:-default}"
    local config_dir="${SCRIPT_DIR}/profiles"

    mkdir -p "$config_dir"
    local config_file="${config_dir}/${profile_name}.conf"

    cat > "$config_file" << EOF
# AMD GPU Batch Converter Profile
# Generated: $(date)
# Profile: $profile_name

CODEC="$CODEC"
PRESET="$PRESET"
QUALITY_VAL="$QUALITY_VAL"
AUDIO_BITRATE="$AUDIO_BITRATE"
CONTAINER="$CONTAINER"
SCALE="$SCALE"
FPS="$FPS"
DEINTERLACE="$DEINTERLACE"
DENOISE="$DENOISE"
CROP="$CROP"
NO_VBAQ="$NO_VBAQ"
NO_PREANALYSIS="$NO_PREANALYSIS"
NO_OPENGOP="$NO_OPENGOP"
TEXTURE_PRESERVE="$TEXTURE_PRESERVE"
TARGET_SIZE="$TARGET_SIZE"
OUTPUT_DIR="$OUTPUT_DIR"
FORCE_PROCESS="$FORCE_PROCESS"
EOF

    log "SUCCESS" "Configuration saved to: $config_file"
}

load_configuration() {
    local profile_name="$1"
    local config_file="${PROFILES_DIR}/${profile_name}.conf"

    if [[ ! -f "$config_file" ]]; then
        config_file="${SCRIPT_DIR}/${profile_name}.conf"
    fi

    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Configuration file not found: $profile_name"
        return 1
    fi

    log "INFO" "Loading configuration: $config_file"
    source "$config_file"
    log "SUCCESS" "Configuration loaded"
}

list_configurations() {
    echo -e "${BLUE}Available Profiles:${NC}" >&2

    if [[ -d "$PROFILES_DIR" ]]; then
        for conf in "$PROFILES_DIR"/*.conf; do
            if [[ -f "$conf" ]]; then
                local name=$(basename "$conf" .conf)
                local preset=$(grep "^PRESET=" "$conf" | cut -d'"' -f2)
                local codec=$(grep "^CODEC=" "$conf" | cut -d'"' -f2)
                local format=$(grep "^CONTAINER=" "$conf" | cut -d'"' -f2)
                echo -e "  ${GREEN}•${NC} $name (${codec}/${preset}/${format})" >&2
            fi
        done
    fi

    for conf in *.conf; do
        if [[ -f "$conf" ]] && [[ "$conf" != "ffmpeg-Batch-convert.conf" ]]; then
            local name=$(basename "$conf" .conf)
            local preset=$(grep "^PRESET=" "$conf" 2>/dev/null | cut -d'"' -f2)
            local codec=$(grep "^CODEC=" "$conf" 2>/dev/null | cut -d'"' -f2)
            local format=$(grep "^CONTAINER=" "$conf" 2>/dev/null | cut -d'"' -f2)
            echo -e "  ${GREEN}•${NC} $name (${codec}/${preset}/${format})" >&2
        fi
    done
}

# ============================================
# GPU Architecture Detection
# ============================================

detect_gpu_architecture() {
    local gpu_model=$(get_amd_gpu_model)
    local architecture="UNKNOWN"

    local gpu_lower=$(echo "$gpu_model" | tr '[:upper:]' '[:lower:]')

    if echo "$gpu_lower" | grep -E "rx (4[0-9]{2}|5[0-9]{2})|polaris" &>/dev/null; then
        architecture="POLARIS"
    elif echo "$gpu_lower" | grep -E "vega|radeon vii" &>/dev/null; then
        architecture="VEGA"
    elif echo "$gpu_lower" | grep -E "rx 5[0-9]{3}|navi 1[0-9]|rdna1" &>/dev/null; then
        architecture="RDNA1"
    elif echo "$gpu_lower" | grep -E "rx 6[0-9]{3}|navi 2[0-9]|rdna2" &>/dev/null; then
        architecture="RDNA2"
    elif echo "$gpu_lower" | grep -E "rx 7[0-9]{3}|navi 3[0-9]|rdna3" &>/dev/null; then
        architecture="RDNA3"
    fi

    echo "$architecture"
}

check_av1_support() {
    local architecture=$(detect_gpu_architecture)

    if [[ "$architecture" == "RDNA3" ]]; then
        if ffmpeg -encoders 2>/dev/null | grep -q "av1_amf\|av1_vaapi"; then
            return 0
        fi
    fi
    return 1
}

get_safe_bframe_settings() {
    local architecture="$1"
    local codec="$2"
    local settings=""

    if [[ -n "${BFRAME_SAFETY[$architecture]:-}" ]]; then
        settings="${BFRAME_SAFETY[$architecture]}"
    else
        settings="${BFRAME_SAFETY[UNKNOWN]}"
    fi

    if [[ "$codec" == "av1" ]]; then
        settings="-bf 3 -refs 4"
    fi

    echo "$settings"
}

# ============================================
# Hardware Detection & Analysis
# ============================================

detect_amd_gpu() {
    if command -v lspci &>/dev/null; then
        if lspci | grep -i "vga.*amd" &>/dev/null || \
           lspci | grep -i "vga.*ati" &>/dev/null || \
           lspci | grep -i "display.*amd" &>/dev/null; then
            return 0
        fi
    fi
    return 1
}

get_amd_gpu_model() {
    if command -v lspci &>/dev/null; then
        lspci | grep -i "vga.*amd\|vga.*ati\|display.*amd" | \
            sed -E 's/.*: (.*)/\1/' | head -1
    else
        echo "Unknown"
    fi
}

check_vaapi_support() {
    if check_command "vainfo"; then
        if vainfo 2>&1 | grep -q "VA-API"; then
            return 0
        fi
    fi
    return 1
}

check_vaapi_encoding_support() {
    local codec="$1"
    local profile=""

    case "$codec" in
        h264) profile="VAProfileH264High" ;;
        hevc) profile="VAProfileHEVCMain" ;;
        av1)  profile="VAProfileAV1Profile0" ;;
        *) return 1 ;;
    esac

    if check_command "vainfo"; then
        if vainfo 2>&1 | grep -q "$profile.*VAEntrypointEncSlice"; then
            return 0
        fi
    fi
    return 1
}

check_vaapi_decode_support() {
    local codec="$1"
    local profile=""

    case "$codec" in
        h264) profile="VAProfileH264" ;;
        hevc) profile="VAProfileHEVC" ;;
        vp9)  profile="VAProfileVP9" ;;
        av1)  profile="VAProfileAV1" ;;
        *) return 1 ;;
    esac

    if check_command "vainfo"; then
        if vainfo 2>&1 | grep -qE "$profile.*VAEntrypointVLD"; then
            return 0
        fi
    fi
    return 1
}

check_amf_support() {
    if ffmpeg -encoders 2>/dev/null | grep -q "h264_amf"; then
        return 0
    fi
    return 1
}

check_amf_encoding_support() {
    local codec="$1"
    if ffmpeg -encoders 2>/dev/null | grep -q "${codec}_amf"; then
        return 0
    fi
    return 1
}

get_vaapi_profiles() {
    if check_command "vainfo"; then
        vainfo 2>/dev/null | grep -E "VAProfile(H.264|HEVC|AV1)" || true
    fi
}

get_render_device() {
    for device in /dev/dri/renderD*; do
        if [[ -e "$device" ]]; then
            if command -v udevadm &>/dev/null; then
                if udevadm info -a -n "$device" 2>/dev/null | grep -qi "amd\|ati"; then
                    echo "$device"
                    return 0
                fi
            else
                echo "$device"
                return 0
            fi
        fi
    done

    for device in /dev/dri/renderD*; do
        if [[ -e "$device" ]]; then
            echo "$device"
            return 0
        fi
    done

    echo ""
}

check_mesa_drivers() {
    if check_command "vainfo"; then
        local va_driver=$(vainfo 2>&1 | grep "vainfo:" | grep "driver" | head -1)
        if echo "$va_driver" | grep -qi "mesa"; then
            log "AMD" "✓ Mesa VA-API driver detected"
            return 0
        fi
    fi
    return 1
}

display_gpu_info() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${CYAN}║                    AMD GPU Information                             ║${NC}" >&2
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}" >&2

    if detect_amd_gpu; then
        local gpu_model=$(get_amd_gpu_model)
        local architecture=$(detect_gpu_architecture)
        local driver_info=$(get_amd_driver_info)

        echo -e "${GREEN}GPU Model:${NC} $gpu_model" >&2
        echo -e "${GREEN}Architecture:${NC} $architecture" >&2
        echo -e "${GREEN}Driver:${NC} $driver_info" >&2

        if check_mesa_drivers; then
            echo -e "${GREEN}Mesa Drivers:${NC} ✓ Installed" >&2
        else
            echo -e "${YELLOW}Mesa Drivers:${NC} ✗ Not detected (may affect performance)" >&2
            echo -e "${YELLOW}  Install with: sudo apt install mesa-va-drivers (Ubuntu/Debian)${NC}" >&2
            echo -e "${YELLOW}  or: sudo dnf install mesa-va-drivers (Fedora)${NC}" >&2
        fi

        if check_vaapi_support; then
            echo -e "${GREEN}VA-API:${NC} ✓ Supported" >&2
            echo -e "${GREEN}VA-API Profiles:${NC}" >&2
            get_vaapi_profiles | while read line; do
                echo "  $line" >&2
            done
        else
            echo -e "${YELLOW}VA-API:${NC} ✗ Not supported" >&2
            echo -e "${YELLOW}  Install VA-API drivers for your distribution${NC}" >&2
        fi

        if check_amf_support; then
            echo -e "${GREEN}AMF:${NC} ✓ Supported" >&2
        else
            echo -e "${YELLOW}AMF:${NC} ✗ Not available (using VA-API)" >&2
        fi

        if check_av1_support; then
            echo -e "${GREEN}AV1 Encoding:${NC} ✓ Supported (RDNA 3)" >&2
        else
            echo -e "${YELLOW}AV1 Encoding:${NC} ✗ Not supported (RDNA 3 required)" >&2
        fi

        local bframes=$(get_safe_bframe_settings "$architecture" "h264")
        echo -e "${GREEN}Safe B-frame settings:${NC} $bframes" >&2

    else
        echo -e "${RED}No AMD GPU detected${NC}" >&2
    fi

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}" >&2
}

detect_hardware_capabilities() {
    log "INFO" "Detecting hardware capabilities..."

    HAS_VAAPI=false
    HAS_AMF=false
    HAS_HEVC_HW=false
    HAS_AV1_HW=false
    HAS_OPEN_GOP=false
    GPU_ARCHITECTURE="UNKNOWN"
    RENDER_DEVICE=""

    if detect_amd_gpu; then
        local gpu_model=$(get_amd_gpu_model)
        GPU_ARCHITECTURE=$(detect_gpu_architecture)
        log "AMD" "AMD GPU detected: ${gpu_model:-Unknown model}"
        log "AMD" "Architecture: $GPU_ARCHITECTURE"

        if check_vaapi_support; then
            log "AMD" "✓ VA-API is supported"
            RENDER_DEVICE=$(get_render_device)
            [[ -n "$RENDER_DEVICE" ]] && log "AMD" "✓ Render device: $RENDER_DEVICE"
            HAS_VAAPI=true

            if check_mesa_drivers; then
                log "AMD" "✓ Mesa VA-API drivers detected"
            fi

            log "DEBUG" "Supported VA-API profiles:"
            get_vaapi_profiles | while read line; do
                log "DEBUG" "  $line"
            done

            if check_vaapi_encoding_support "hevc"; then
                log "AMD" "✓ HEVC hardware encoding supported"
                HAS_HEVC_HW=true
            fi

            if check_vaapi_encoding_support "av1"; then
                log "AMD" "✓ AV1 hardware encoding supported"
                HAS_AV1_HW=true
            fi
        else
            log "WARN" "VA-API not supported. Install mesa-va-drivers for your distribution."
            log "WARN" "  Ubuntu/Debian: sudo apt install mesa-va-drivers"
            log "WARN" "  Fedora: sudo dnf install mesa-va-drivers"
            log "WARN" "  Arch: sudo pacman -S libva-mesa-driver"
            HAS_VAAPI=false
        fi

        if check_amf_support; then
            log "AMD" "✓ AMF encoder is available (proprietary path)"
            HAS_AMF=true

            if check_amf_encoding_support "hevc"; then
                HAS_HEVC_HW=true
            fi
            if check_amf_encoding_support "av1"; then
                HAS_AV1_HW=true
            fi
        else
            log "DEBUG" "AMF not available, using VA-API (open source path)"
            HAS_AMF=false
        fi

        if ffmpeg -h encoder=h264_amf 2>&1 | grep -q "open_gop"; then
            log "AMD" "✓ Open GOP supported"
            HAS_OPEN_GOP=true
        fi

        local safe_bframes=$(get_safe_bframe_settings "$GPU_ARCHITECTURE" "h264")
        log "AMD" "Safe B-frame settings: $safe_bframes"

    else
        log "WARN" "No AMD GPU detected. Falling back to CPU encoding."
        GPU_ARCHITECTURE="UNKNOWN"
        HAS_AMD=false
        HAS_VAAPI=false
        HAS_AMF=false
        HAS_HEVC_HW=false
        HAS_AV1_HW=false
    fi
}

# ============================================
# Format Detection and Validation
# ============================================

is_valid_output_format() {
    local format="$1"
    [[ -n "${OUTPUT_FORMATS[$format]:-}" ]]
}

get_default_codec_for_format() {
    local format="$1"
    echo "${OUTPUT_FORMATS[$format]:-h264}"
}

validate_codec_for_format() {
    local codec="$1"
    local format="$2"

    if [[ -n "${FORMAT_COMPATIBILITY[$format]:-}" ]]; then
        if echo "${FORMAT_COMPATIBILITY[$format]}" | grep -qw "$codec"; then
            return 0
        fi
    fi
    return 1
}

# ============================================
# FFmpeg Command Generation
# ============================================

calculate_bitrate_for_target_size() {
    local input_file="$1"
    local target_size="$2"
    local duration

    if ! check_command "bc"; then
        log "ERROR" "bc calculator not found. Please install bc first."
        log "INFO" "Run: sudo $SCRIPT_NAME --install-deps"
        return 1
    fi

    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null | head -1)

    if [[ -z "$duration" || "$duration" == "N/A" || "$duration" == "0" || "$duration" == "0.00" ]]; then
        log "WARN" "Duration not available, estimating based on typical DVD bitrate"
        duration="5400"
    fi

    if [[ -n "$duration" ]] && [[ -n "$target_size" ]]; then
        local size_num="${target_size%[a-zA-Z]}"
        local size_unit="${target_size//[0-9.]/}"

        case "${size_unit^^}" in
            "K"|"KB") target_bits=$(echo "$size_num * 1024 * 8" | bc 2>/dev/null) ;;
            "M"|"MB") target_bits=$(echo "$size_num * 1024 * 1024 * 8" | bc 2>/dev/null) ;;
            "G"|"GB") target_bits=$(echo "$size_num * 1024 * 1024 * 1024 * 8" | bc 2>/dev/null) ;;
            *) target_bits=$(echo "$size_num * 1024 * 1024 * 8" | bc 2>/dev/null) ;;
        esac

        local bitrate=$(echo "$target_bits / $duration" | bc 2>/dev/null)
        echo $(echo "$bitrate / 1024" | bc 2>/dev/null)
    else
        echo ""
    fi
}

get_amd_driver_info() {
    if [[ -d "/sys/module/amdgpu" ]]; then
        local version=$(cat /sys/module/amdgpu/version 2>/dev/null || echo "unknown")
        echo "amdgpu kernel driver (version: $version)"
    elif [[ -d "/sys/module/radeon" ]]; then
        echo "radeon kernel driver (legacy)"
    else
        echo "unknown"
    fi
}

is_vob_file() {
    local filename="$1"
    local extension="${filename##*.}"
    extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
    [[ "$extension" == "vob" ]]
}

probe_video_codec() {
    local input_file="$1"
    ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_name -of default=nokey=1:nokey=1 \
        "$input_file" 2>/dev/null | head -1
}

build_ffmpeg_command() {
    local input_file="$1"
    local output_file="$2"
    local cmd="ffmpeg"

    if [[ "${DEBUG:-false}" != "true" ]]; then
        cmd+=" -loglevel error -stats"
    fi

    if is_vob_file "$input_file" && [[ "${FORCE_PROCESS:-false}" == "true" ]]; then
        log "WARN" "Forced processing enabled for VOB file - ignoring duration check"
        cmd+=" -fflags +genpts+igndts"
    fi

    if [[ -n "${TARGET_SIZE:-}" ]]; then
        local calculated_bitrate=$(calculate_bitrate_for_target_size "$input_file" "$TARGET_SIZE")
        if [[ -n "$calculated_bitrate" ]]; then
            log "INFO" "Target size: $TARGET_SIZE, calculated bitrate: ${calculated_bitrate}k"
            USE_TARGET_BITRATE=true
            TARGET_VIDEO_BITRATE="$calculated_bitrate"
        fi
    fi

    local input_codec=""
    if [[ "${NO_HWACCEL:-false}" != "true" ]] && [[ "${HAS_VAAPI:-false}" == "true" ]]; then
        input_codec=$(probe_video_codec "$input_file" || true)
    fi

    if [[ "${NO_HWACCEL:-false}" != "true" ]] && [[ "${HAS_VAAPI:-false}" == "true" ]]; then
        local driver_info=$(get_amd_driver_info)
        log "DEBUG" "Using AMD driver: $driver_info"

        if [[ "${USE_AMF:-false}" == "true" ]] && [[ "${HAS_AMF:-false}" == "true" ]] && check_amf_encoding_support "$CODEC"; then
            log "AMD" "Using AMF hardware encoding pipeline"
            cmd+=" -i \"$input_file\""
            cmd+=" -c:v ${CODEC}_amf"

            if [[ "${USE_TARGET_BITRATE:-false}" == "true" ]]; then
                cmd+=" -rc vbr_peak -b:v ${TARGET_VIDEO_BITRATE}k -maxrate $((TARGET_VIDEO_BITRATE * 2))k -bufsize $((TARGET_VIDEO_BITRATE * 4))k"
            elif [[ "$CODEC" == "av1" ]] && [[ -n "${AV1_QUALITY_PRESETS[$PRESET]:-}" ]]; then
                cmd+=" ${AV1_QUALITY_PRESETS[$PRESET]}"
            elif [[ -n "${QUALITY_PRESETS[$PRESET]:-}" ]]; then
                cmd+=" ${QUALITY_PRESETS[$PRESET]}"
            fi

            if [[ -n "${QUALITY_VAL:-}" ]] && [[ "${USE_TARGET_BITRATE:-false}" != "true" ]]; then
                if [[ "$PRESET" == "maxquality" ]] || [[ "$PRESET" == "cqp"* ]]; then
                    if [[ "$CODEC" == "av1" ]]; then
                        cmd+=" -qp $QUALITY_VAL"
                    else
                        cmd+=" -qp_i $QUALITY_VAL -qp_p $QUALITY_VAL -qp_b $((QUALITY_VAL + 2))"
                    fi
                else
                    cmd+=" -qvbr_quality_level $QUALITY_VAL"
                fi
            fi

            if [[ "${TEXTURE_PRESERVE:-false}" == "true" ]]; then
                cmd+=" ${TEXTURE_SETTINGS[preserve]}"
            fi

            local safe_bframes=$(get_safe_bframe_settings "$GPU_ARCHITECTURE" "$CODEC")
            cmd+=" $safe_bframes"

            if [[ "${NO_VBAQ:-false}" == "true" ]]; then
                cmd=${cmd/"-vbaq 1"/"-vbaq 0"}
            fi

            if [[ "${NO_PREANALYSIS:-false}" == "true" ]]; then
                cmd=${cmd/"-preanalysis 1"/"-preanalysis 0"}
            fi

            if [[ "${NO_OPENGOP:-false}" == "true" ]]; then
                cmd=${cmd/"-open_gop 1"/"-open_gop 0"}
            fi

        elif check_vaapi_encoding_support "$CODEC"; then
            log "AMD" "Using VA-API hardware encoding pipeline"

            local hwdec_enabled=false
            if [[ "$input_codec" == "h264" || "$input_codec" == "hevc" ]]; then
                if check_vaapi_decode_support "$input_codec"; then
                    log "AMD" "Hardware decode enabled for input: $input_codec"
                    cmd+=" -hwaccel vaapi -hwaccel_device $RENDER_DEVICE -hwaccel_output_format vaapi"
                    hwdec_enabled=true
                fi
            fi

            cmd+=" -vaapi_device $RENDER_DEVICE -i \"$input_file\""

            local filters="format=nv12,hwupload"
            if [[ "$hwdec_enabled" == "true" ]]; then
                filters=""
            fi

            if [[ "${DEINTERLACE:-false}" == "true" ]] || is_vob_file "$input_file"; then
                if is_vob_file "$input_file" && [[ "${DEINTERLACE:-false}" != "true" ]]; then
                    log "INFO" "Auto-enabling deinterlacing for DVD/VOB file"
                fi
                if [[ -n "$filters" ]]; then
                    filters="deinterlace_vaapi,$filters"
                else
                    filters="deinterlace_vaapi"
                fi
            fi

            if [[ -n "${DENOISE:-}" ]]; then
                case "$DENOISE" in
                    low)    filters="denoise_vaapi=level=4${filters:+,$filters}" ;;
                    medium) filters="denoise_vaapi=level=8${filters:+,$filters}" ;;
                    high)   filters="denoise_vaapi=level=16${filters:+,$filters}" ;;
                esac
            fi

            if [[ -n "${SCALE:-}" ]]; then
                filters="scale_vaapi=$SCALE${filters:+,$filters}"
            fi

            if [[ -n "${CROP:-}" ]]; then
                filters="crop_vaapi=$CROP${filters:+,$filters}"
            fi

            if [[ -n "${FPS:-}" ]]; then
                filters="fps=$FPS${filters:+,$filters}"
            fi

            if [[ -n "$filters" ]]; then
                cmd+=" -vf \"$filters\""
            fi

            cmd+=" -c:v ${CODEC}_vaapi"

            if [[ -n "${VAAPI_QUALITY_PRESETS[$PRESET]:-}" ]]; then
                cmd+=" ${VAAPI_QUALITY_PRESETS[$PRESET]}"
            fi

            if [[ "${USE_TARGET_BITRATE:-false}" == "true" ]]; then
                cmd+=" -b:v ${TARGET_VIDEO_BITRATE}k"
            fi

            local safe_bframes=$(get_safe_bframe_settings "$GPU_ARCHITECTURE" "$CODEC")
            cmd+=" $safe_bframes"
        else
            log "WARN" "Hardware encoding not available for $CODEC, falling back to CPU"
            USE_AMF=false
            HAS_VAAPI=false
        fi
    fi

    if [[ "${NO_HWACCEL:-false}" == "true" ]] || [[ "${HAS_VAAPI:-false}" != "true" ]]; then
        log "INFO" "Using CPU encoding"
        cmd+=" -i \"$input_file\""

        if [[ "$CODEC" == "av1" ]]; then
            cmd+=" -c:v libaom-av1 -crf 30 -cpu-used 4 -b:v 0"
        elif [[ "$CODEC" == "vp9" ]]; then
            cmd+=" -c:v libvpx-vp9 -crf 30 -b:v 0 -cpu-used 4 -row-mt 1"
        elif [[ "$CODEC" == "theora" ]]; then
            cmd+=" -c:v libtheora -q:v 7"
        else
            cmd+=" -c:v libx${CODEC}"

            if [[ -n "${QUALITY_VAL:-}" ]]; then
                cmd+=" -crf $QUALITY_VAL"
            else
                case "$PRESET" in
                    maxquality)      cmd+=" -crf 16 -preset slow" ;;
                    balanced)        cmd+=" -crf 22 -preset medium" ;;
                    fast)            cmd+=" -crf 26 -preset fast" ;;
                    highcompression) cmd+=" -crf 28 -preset veryslow" ;;
                    streaming)       cmd+=" -crf 23 -preset medium" ;;
                    dvd)             cmd+=" -crf 22 -preset medium" ;;
                esac
            fi

            cmd+=" -tune film -profile:v high -level 4.1"

            if [[ -n "${BFRAME_SETTINGS[$CODEC]:-}" ]]; then
                cmd+=" ${BFRAME_SETTINGS[$CODEC]}"
            fi
        fi

        if [[ "${USE_TARGET_BITRATE:-false}" == "true" ]]; then
            cmd+=" -b:v ${TARGET_VIDEO_BITRATE}k"
        fi

        local cpu_filters=""
        if [[ -n "${DEINTERLACE:-}" && "${DEINTERLACE:-false}" == "true" ]] || is_vob_file "$input_file"; then
            cpu_filters="yadif${cpu_filters:+,$cpu_filters}"
        fi
        if [[ -n "${DENOISE:-}" ]]; then
            case "$DENOISE" in
                low)    cpu_filters="hqdn3d=1.5:1.5:6:6${cpu_filters:+,$cpu_filters}" ;;
                medium) cpu_filters="hqdn3d=3:3:9:9${cpu_filters:+,$cpu_filters}" ;;
                high)   cpu_filters="hqdn3d=5:5:12:12${cpu_filters:+,$cpu_filters}" ;;
            esac
        fi
        if [[ -n "${SCALE:-}" ]]; then
            cpu_filters="scale=$SCALE${cpu_filters:+,$cpu_filters}"
        fi
        if [[ -n "${CROP:-}" ]]; then
            cpu_filters="crop=$CROP${cpu_filters:+,$cpu_filters}"
        fi
        if [[ -n "${FPS:-}" ]]; then
            cpu_filters="fps=$FPS${cpu_filters:+,$cpu_filters}"
        fi
        if [[ -n "$cpu_filters" ]]; then
            cmd+=" -vf \"$cpu_filters\""
        fi
    fi

    local audio_codec="${AUDIO_CODECS[$CONTAINER]:-aac}"
    if [[ "$audio_codec" == "libopus" ]]; then
        cmd+=" -c:a libopus -b:a $AUDIO_BITRATE -strict -2"
    else
        cmd+=" -c:a $audio_codec -b:a $AUDIO_BITRATE"
    fi

    if [[ -n "${TRIM:-}" ]]; then
        cmd+=" -ss ${TRIM%:*} -t ${TRIM#*:}"
    fi

    if [[ "$CONTAINER" == "mp4" || "$CONTAINER" == "m4v" || "$CONTAINER" == "mov" ]]; then
        cmd+=" -movflags +faststart"
    fi

    if [[ "$CONTAINER" != "webm" && "$CONTAINER" != "ogv" ]]; then
        cmd+=" -map_metadata 0"
    fi

    if [[ "$CONTAINER" == "mp4" || "$CONTAINER" == "m4v" || "$CONTAINER" == "mov" ]]; then
        cmd+=" -map 0:v:0? -map 0:a:0?"
    fi

    cmd+=" \"$output_file\""

    echo "$cmd"
}

# ============================================
# File Processing
# ============================================

get_file_info() {
    local input_file="$1"

    if check_command "ffprobe"; then
        local duration=$(ffprobe -v error -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null | head -1)

        local video_codec=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null | head -1)

        local resolution=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=width,height -of csv=p=0 "$input_file" 2>/dev/null | head -1 | tr ',' 'x')

        local bitrate=$(ffprobe -v error -show_entries format=bit_rate \
            -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null | head -1)

        video_codec="${video_codec:-unknown}"
        resolution="${resolution:-unknown}"
        duration="${duration:-0}"
        bitrate="${bitrate:-0}"

        if [[ "$duration" == "0" || "$duration" == "0.00" || -z "$duration" || "$duration" == "N/A" ]]; then
            if is_vob_file "$input_file"; then
                log "WARN" "VOB file has malformed duration header"
                if [[ "${FORCE_PROCESS:-false}" == "true" ]]; then
                    log "INFO" "Forced processing enabled - will attempt conversion anyway"
                    duration="1.00"
                else
                    log "WARN" "Use --force-process to attempt conversion of this VOB file"
                fi
            fi
        fi

        local duration_formatted="0.00"
        if [[ "$duration" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            duration_formatted=$(printf "%.2f" "$duration" 2>/dev/null || echo "0.00")
        fi

        local bitrate_formatted="$bitrate"
        if [[ "$bitrate" =~ ^[0-9]+$ ]]; then
            if [[ $bitrate -gt 1000000 ]]; then
                bitrate_formatted="$(echo "scale=1; $bitrate/1000000" | bc 2>/dev/null || echo "$bitrate") Mbps"
            elif [[ $bitrate -gt 1000 ]]; then
                bitrate_formatted="$(echo "scale=1; $bitrate/1000" | bc 2>/dev/null || echo "$bitrate") Kbps"
            fi
        else
            bitrate_formatted="N/A"
        fi

        log "INFO" "Input: ${video_codec} | ${resolution} | ${duration_formatted}s | ${bitrate_formatted}"
    fi
}

process_file() {
    local input_file="$1"
    local output_subdir="$OUTPUT_DIR"

    if [[ ! -f "$input_file" ]]; then
        log "WARN" "Skipping non-existent file: $input_file"
        return 0
    fi

    if [[ "${KEEP_TREE:-false}" == "true" ]]; then
        local rel_path="${input_file#./}"
        output_subdir="$OUTPUT_DIR/$(dirname "$rel_path")"
    fi

    mkdir -p "$output_subdir"

    local input_base
    input_base=$(basename "$input_file")
    local filename="${input_base%.*}"
    local output_file="$output_subdir/${filename}.${CONTAINER}"

    if [[ -f "$output_file" ]] && [[ "${FORCE:-false}" != "true" ]]; then
        log "WARN" "Output file exists, skipping (use --force to overwrite): $output_file"
        return 0
    fi

    log "INFO" "Processing: $input_file"
    get_file_info "$input_file"
    log "INFO" "Output: $output_file"

    local cmd=$(build_ffmpeg_command "$input_file" "$output_file")

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} FFmpeg command:" >&2
        echo "$cmd"
        return 0
    fi

    log "DEBUG" "Running: $cmd"

    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log "SUCCESS" "✓ Successfully converted: $input_file"
        if [[ -f "$output_file" ]]; then
            local size=$(du -h "$output_file" | cut -f1)
            log "INFO" "  Output size: $size"

            local input_size=$(du -b "$input_file" | cut -f1)
            local output_size=$(du -b "$output_file" | cut -f1)
            if [[ -n "$input_size" ]] && [[ -n "$output_size" ]] && [[ $input_size -gt 0 ]]; then
                local ratio=$(echo "scale=2; $output_size * 100 / $input_size" | bc 2>/dev/null || echo "0")
                log "INFO" "  Compression: ${ratio}% of original"
            fi
        fi
        return 0
    else
        log "ERROR" "✗ Failed to convert: $input_file"
        if [[ -f "$LOG_FILE" ]]; then
            log "DEBUG" "Last 5 lines of log:"
            tail -5 "$LOG_FILE" | while read line; do
                log "DEBUG" "  $line"
            done
        fi

        if is_vob_file "$input_file" && [[ "${FORCE_PROCESS:-false}" != "true" ]]; then
            log "INFO" "Tip: VOB files often need forced processing. Try:"
            log "INFO" "  $SCRIPT_NAME --force-process -p dvd \"$input_file\" to $CONTAINER"
        fi

        return 1
    fi
}

process_files() {
    local files=("$@")

    mkdir -p "$OUTPUT_DIR"

    log "INFO" "Found ${#files[@]} files to process"

    local success_count=0
    local fail_count=0
    local skip_count=0
    local start_time=$(date +%s)

    for file in "${files[@]}"; do
        echo "-----------------------------------" >&2
        # IMPORTANT: use `x=$((x + 1))`, NOT `((x++))`.
        # Under `set -e`, `((x++))` returns non-zero when x was 0, which
        # aborts the entire script right after the first file.
        if process_file "$file"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    local minutes=$((total_time / 60))
    local seconds=$((total_time % 60))

    echo "===================================" >&2
    log "INFO" "=== Conversion Complete ==="
    log "SUCCESS" "Successful: $success_count"
    [[ $fail_count -gt 0 ]] && log "ERROR" "Failed: $fail_count"
    log "INFO" "Total time: ${minutes}m ${seconds}s"
    log "INFO" "Log file: $LOG_FILE"
    echo "===================================" >&2
}

# ============================================
# Main Script with Format Detection
# ============================================

main() {
    # ------------------------------------------------------------------
    # Safe "to FORMAT" parsing — no eval, preserves filenames with spaces
    # ------------------------------------------------------------------
    local -a clean_args=()
    local next_is_format=0
    local found_format=""
    for arg in "$@"; do
        if [[ $next_is_format -eq 1 ]]; then
            found_format="$arg"
            next_is_format=0
            continue
        fi
        if [[ "$arg" == "to" ]]; then
            next_is_format=1
            continue
        fi
        clean_args+=("$arg")
    done

    if [[ -n "$found_format" ]]; then
        if is_valid_output_format "$found_format"; then
            CONTAINER="$found_format"
            if [[ -z "${CODEC:-}" ]]; then
                CODEC="$(get_default_codec_for_format "$CONTAINER")"
            fi
            log "INFO" "Detected output format: $CONTAINER (using $CODEC codec)"
            if [[ ${#clean_args[@]} -gt 0 ]]; then
                set -- "${clean_args[@]}"
            else
                set --
            fi
        else
            log "ERROR" "Invalid output format after 'to': $found_format"
            echo "Supported formats: ${!OUTPUT_FORMATS[*]}" >&2
            exit 1
        fi
    else
        if [[ ${#clean_args[@]} -gt 0 ]]; then
            set -- "${clean_args[@]}"
        fi
    fi

    # Parse command line arguments
    local files=()
    local use_all_keyword=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_banner
                print_usage
                exit 0
                ;;
            -v|--version)
                print_version
                exit 0
                ;;
            -d|--debug)
                DEBUG=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --check-deps)
                check_dependencies
                exit $?
                ;;
            --install-deps)
                install_dependencies
                exit $?
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -c|--codec)
                CODEC="$2"
                shift 2
                ;;
            -p|--preset)
                PRESET="$2"
                shift 2
                ;;
            -q|--quality)
                QUALITY_VAL="$2"
                shift 2
                ;;
            -a|--audio-bitrate)
                AUDIO_BITRATE="$2"
                shift 2
                ;;
            -f|--format)
                CONTAINER="$2"
                shift 2
                ;;
            -r|--resolution)
                if [[ -n "${RESOLUTION_PRESETS[$2]:-}" ]]; then
                    SCALE="${RESOLUTION_PRESETS[$2]}"
                else
                    SCALE="$2"
                fi
                shift 2
                ;;
            --keep-tree)
                KEEP_TREE=true
                shift
                ;;
            --no-hwaccel)
                NO_HWACCEL=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --scale)
                SCALE="$2"
                shift 2
                ;;
            --fps)
                FPS="$2"
                shift 2
                ;;
            --trim)
                TRIM="$2"
                shift 2
                ;;
            --deinterlace)
                DEINTERLACE=true
                shift
                ;;
            --denoise)
                DENOISE="$2"
                shift 2
                ;;
            --crop)
                CROP="$2"
                shift 2
                ;;
            --no-vbaq)
                NO_VBAQ=true
                shift
                ;;
            --no-preanalysis)
                NO_PREANALYSIS=true
                shift
                ;;
            --no-opengop)
                NO_OPENGOP=true
                shift
                ;;
            --texture-preserve)
                TEXTURE_PRESERVE=true
                shift
                ;;
            --target-size)
                TARGET_SIZE="$2"
                shift 2
                ;;
            --force-process)
                FORCE_PROCESS=true
                shift
                ;;
            --no-filter)
                NO_FILTER=true
                shift
                ;;
            --all)
                # Flag form of the `all` keyword
                use_all_keyword=true
                shift
                ;;
            --conf)
                interactive_menu
                exit 0
                ;;
            --save-conf)
                save_configuration "$2"
                shift 2
                ;;
            --load-conf)
                load_configuration "$2"
                shift 2
                ;;
            --list-conf)
                list_configurations
                exit 0
                ;;
            --gpu-info)
                display_gpu_info
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                # Positional `all` keyword: convert every video in cwd.
                # Only treat the literal string "all" as the keyword if
                # no file named "all" exists in the current directory.
                if [[ "$1" == "all" && ! -f "all" ]]; then
                    use_all_keyword=true
                else
                    files+=("$1")
                fi
                shift
                ;;
        esac
    done

    print_banner

    if ! check_command "bc"; then
        log "ERROR" "bc calculator not found. This is required for bitrate calculation."
        log "INFO" "Please install bc first:"
        log "INFO" "  sudo $SCRIPT_NAME --install-deps"
        log "INFO" "Or run: sudo ./$SCRIPT_NAME --install-deps"
        exit 1
    fi

    CODEC="${CODEC:-$DEFAULT_CODEC}"
    PRESET="${PRESET:-$DEFAULT_QUALITY}"
    AUDIO_BITRATE="${AUDIO_BITRATE:-$DEFAULT_AUDIO_BITRATE}"
    CONTAINER="${CONTAINER:-$DEFAULT_CONTAINER}"

    if ! is_valid_output_format "$CONTAINER"; then
        log "ERROR" "Invalid output format: $CONTAINER"
        echo "Supported formats: ${!OUTPUT_FORMATS[*]}" >&2
        exit 1
    fi

    if ! validate_codec_for_format "$CODEC" "$CONTAINER"; then
        log "WARN" "Codec $CODEC may not be compatible with $CONTAINER format"
        log "WARN" "Compatible codecs for $CONTAINER: ${FORMAT_COMPATIBILITY[$CONTAINER]}"
        if command -v gum &>/dev/null; then
            if gum confirm "Continue anyway?" --default=false; then
                log "INFO" "Continuing with $CODEC/$CONTAINER combination"
            else
                exit 1
            fi
        else
            log "WARN" "Continuing anyway (use --conf for interactive mode)"
        fi
    fi

    if [[ "$CODEC" != "h264" ]] && [[ "$CODEC" != "hevc" ]] && [[ "$CODEC" != "av1" ]] && [[ "$CODEC" != "vp9" ]] && [[ "$CODEC" != "theora" ]]; then
        log "ERROR" "Invalid codec: $CODEC (must be h264, hevc, av1, vp9, or theora)"
        exit 1
    fi

    if [[ -z "${QUALITY_PRESETS[$PRESET]:-}" ]] && [[ -z "${VAAPI_QUALITY_PRESETS[$PRESET]:-}" ]] && [[ -z "${AV1_QUALITY_PRESETS[$PRESET]:-}" ]]; then
        log "ERROR" "Invalid preset: $PRESET"
        echo "Valid presets: ${!QUALITY_PRESETS[*]}" >&2
        exit 1
    fi

    if [[ -n "${DENOISE:-}" ]]; then
        case "$DENOISE" in
            low|medium|high) ;;
            *)
                log "ERROR" "Invalid denoise level: $DENOISE (must be low, medium, or high)"
                exit 1
                ;;
        esac
    fi

    if [[ -n "${QUALITY_VAL:-}" ]]; then
        if [[ "$QUALITY_VAL" -lt 16 ]] || [[ "$QUALITY_VAL" -gt 32 ]]; then
            log "WARN" "Quality value $QUALITY_VAL is outside recommended range (16-32)"
        fi
    fi

    touch "$LOG_FILE"
    log "INFO" "=== Starting AMD GPU Batch Conversion v${VERSION} ==="
    log "INFO" "Log file: $LOG_FILE"

    # ------------------------------------------------------------------
    # `all` keyword expansion
    # ------------------------------------------------------------------
    if [[ "$use_all_keyword" == "true" ]]; then
        log "INFO" "Scanning current directory for supported video files..."
        while IFS= read -r line; do
            [[ -n "$line" ]] && files+=("$line")
        done < <(collect_all_videos_in_cwd)
        log "INFO" "The 'all' keyword matched ${#files[@]} video file(s)"
    fi

    # ------------------------------------------------------------------
    # If no files given on the command line, fall back to scanning the
    # current directory (same behaviour as `all`).
    # ------------------------------------------------------------------
    if [[ ${#files[@]} -eq 0 ]] && [[ "$use_all_keyword" != "true" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && files+=("$line")
        done < <(collect_all_videos_in_cwd)
    fi

    # ------------------------------------------------------------------
    # Filter out non-video files. This makes `./script.sh * to mp4` safe:
    # the script itself, READMEs, .conf files, logs, and directories are
    # quietly skipped instead of being fed to ffmpeg.
    # ------------------------------------------------------------------
    if [[ "${NO_FILTER:-false}" != "true" ]] && [[ ${#files[@]} -gt 0 ]]; then
        local -a accepted_files=()
        local -a rejected_files=()
        local f
        for f in "${files[@]}"; do
            if is_supported_input_file "$f"; then
                accepted_files+=("$f")
            elif [[ -e "$f" ]]; then
                rejected_files+=("$f")
            fi
        done

        if [[ ${#rejected_files[@]} -gt 0 ]]; then
            log "INFO" "Skipped ${#rejected_files[@]} non-video file(s) — run with -d to list them"
            for f in "${rejected_files[@]}"; do
                log "DEBUG" "  Skipped (unsupported extension): $f"
            done
        fi

        # Safe empty-array assignment under set -u (bash < 4.4)
        if [[ ${#accepted_files[@]} -gt 0 ]]; then
            files=("${accepted_files[@]}")
        else
            files=()
        fi
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        log "ERROR" "No input files found"
        print_usage
        exit 1
    fi

    if ! check_command "ffmpeg"; then
        log "WARN" "FFmpeg not found. Attempting to install dependencies..."
        install_dependencies

        if ! check_command "ffmpeg"; then
            log "ERROR" "FFmpeg installation failed. Please install manually."
            exit 1
        fi
    fi

    detect_hardware_capabilities

    if [[ "$CODEC" == "av1" ]] && [[ "${HAS_AV1_HW:-false}" != "true" ]]; then
        log "WARN" "AV1 hardware encoding not supported on this GPU. Falling back to CPU (libaom-av1)."
        NO_HWACCEL=true
    fi

    if [[ "$CODEC" == "vp9" || "$CODEC" == "theora" ]]; then
        log "INFO" "$CODEC encoding is CPU-based (no hardware acceleration)"
        NO_HWACCEL=true
    fi

    if [[ "$NO_HWACCEL" == "true" ]]; then
        USE_AMF=false
        log "INFO" "Hardware acceleration disabled, using CPU encoding"
    else
        if [[ "${HAS_AMF:-false}" == "true" ]] && check_amf_encoding_support "$CODEC"; then
            USE_AMF=true
            log "AMD" "Using AMF hardware encoding (proprietary driver path)"
        elif [[ "${HAS_VAAPI:-false}" == "true" ]] && check_vaapi_encoding_support "$CODEC"; then
            USE_AMF=false
            log "AMD" "Using VA-API hardware encoding (open source driver path)"
        else
            USE_AMF=false
            log "WARN" "Hardware encoding not available for $CODEC, falling back to CPU"
            NO_HWACCEL=true
        fi
    fi

    if [[ -n "${GPU_ARCHITECTURE:-}" ]] && [[ "$GPU_ARCHITECTURE" != "UNKNOWN" ]]; then
        log "AMD" "GPU Architecture: $GPU_ARCHITECTURE"
        local safe_bframes=$(get_safe_bframe_settings "$GPU_ARCHITECTURE" "$CODEC")
        log "AMD" "Using B-frame settings: $safe_bframes"
    fi

    log "INFO" "Encoding settings:"
    log "INFO" "  • Format: $CONTAINER"
    log "INFO" "  • Codec: $CODEC"
    log "INFO" "  • Preset: $PRESET"
    [[ -n "${QUALITY_VAL:-}" ]] && log "INFO" "  • Quality: $QUALITY_VAL"
    [[ -n "${SCALE:-}" ]] && log "INFO" "  • Resolution: $SCALE"
    [[ -n "${TARGET_SIZE:-}" ]] && log "INFO" "  • Target size: $TARGET_SIZE"
    log "INFO" "  • Audio codec: ${AUDIO_CODECS[$CONTAINER]:-aac} @ $AUDIO_BITRATE"
    [[ "${NO_VBAQ:-false}" == "true" ]] && log "INFO" "  • VBAQ: Disabled" || log "INFO" "  • VBAQ: Enabled"
    [[ "${NO_PREANALYSIS:-false}" == "true" ]] && log "INFO" "  • Pre-analysis: Disabled" || log "INFO" "  • Pre-analysis: Enabled"
    [[ "${NO_OPENGOP:-false}" == "true" ]] && log "INFO" "  • Open GOP: Disabled" || log "INFO" "  • Open GOP: Enabled"
    [[ "${TEXTURE_PRESERVE:-false}" == "true" ]] && log "INFO" "  • Texture preservation: Enabled"
    [[ "${FORCE_PROCESS:-false}" == "true" ]] && log "INFO" "  • Force processing: Enabled (for VOB files)"

    process_files "${files[@]}"

    # Not reached if process_files uses `set -e`-safe counter increments
    # (it does, as of v1.1.11), so exit here with the proper status.
    # We compute the status from the last conversion summary.
    # Since process_files runs in the same shell (no subshell), any
    # non-zero exit would already have aborted under `set -e`. We just
    # exit 0 here; individual failures were logged.
    exit 0
}

# Run main function
main "$@"
