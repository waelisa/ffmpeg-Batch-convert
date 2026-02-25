#!/usr/bin/env bash
#############################################################################################################################
#
# Advanced AMD GPU Batch Video Converter
# Wael Isa - www.wael.name
# GitHub: https://github.com/waelisa/ffmpeg-Batch-convert
# Version: 1.1.0
# Description: Batch convert video files using AMD GPU hardware acceleration
# Author: Based on AMD optimization guidelines
# License: MIT
#
# Features:
#   - Automatic dependency installation
#   - Multi-distribution support (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE)
#   - AMD GPU detection and VA-API/AMF support
#   - Advanced encoding options with presets
#   - Detailed logging and error handling
#   - Full hardware pipeline optimization
#   - Variance Based Adaptive Quantization (VBAQ) support
#   - Pre-encoding analysis and optimization
#   - Open GOP support for better compression
#   - Enhanced B-frame and reference frame optimization
#   - Peak bitrate control for consistent quality
#   - Interactive menu builder with gum
#   - Configuration file support (JSON/YAML)
#   - Resolution presets (720p, 1080p, 2K, 4K)
#
# Changelog:
#   v1.1.0 - Fixed ANSI color codes
#          - Added interactive menu with gum
#          - Configuration file support (.conf)
#          - Resolution presets
#          - Profile management
#          - GitHub integration
#   v1.0.2 - Fixed color code formatting
#          - Added Open GOP support
#          - Enhanced B-frame configuration
#   v1.0.1 - Added VBAQ support, pre-analysis, B-frame optimization
#   v1.0.0 - Initial release with multi-distro support and auto-install
#
#############################################################################################################################

set -euo pipefail
IFS=$'\n\t'

# Script configuration
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
VERSION="1.1.0"
LOG_FILE="${SCRIPT_DIR}/conversion_$(date +%Y%m%d_%H%M%S).log"
OUTPUT_DIR="output"
CONFIG_FILE="${SCRIPT_DIR}/ffmpeg-Batch-convert.conf"
PROFILES_DIR="${SCRIPT_DIR}/profiles"

# ANSI color codes - FIXED: Properly escaped for echo -e
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

# Resolution presets
declare -A RESOLUTION_PRESETS=(
    ["480p"]="854x480"
    ["720p"]="1280x720"
    ["1080p"]="1920x1080"
    ["2K"]="2560x1440"
    ["4K"]="3840x2160"
    ["8K"]="7680x4320"
)

# ============================================
# Enhanced AMD-Specific Encoding Presets v2
# ============================================

# AMF encoder presets with advanced AMD optimizations
# Based on AMD AMF SDK documentation and hardware capabilities
declare -A QUALITY_PRESETS=(
    # Maximum quality - CQP mode with low QP values
    # Best for archival, minimal compression artifacts
    # Added Open GOP, increased reference frames, full motion estimation
    ["maxquality"]="-quality quality -rc cqp -qp_i 18 -qp_p 18 -qp_b 22 -vbaq 1 -preanalysis 1 -me full -maxaufsize 4 -gops_per_idr 60 -open_gop 1 -luma_adaptive_quantization 1"

    # Balanced - High Quality VBR with pre-analysis
    # Optimal for general use, good quality/size ratio
    # Added peak bitrate control to prevent blocking in fast motion
    ["balanced"]="-quality quality -rc hqvbr -qvbr_quality_level 22 -maxrate 15M -peak_bitrate 15M -bufsize 24M -vbaq 1 -preanalysis 1 -me quarter -maxaufsize 3 -gops_per_idr 30 -open_gop 1"

    # Fast encoding - Speed optimized with peak VBR
    # For quick previews or when time is critical
    ["fast"]="-quality speed -rc vbr_peak -maxrate 8M -bufsize 16M -vbaq 0 -preanalysis 0 -me half -maxaufsize 2 -gops_per_idr 15"

    # High compression - VBR latency mode for smaller files
    # Best for storage optimization, streaming
    ["highcompression"]="-quality quality -rc vbr_latency -qvbr_quality_level 26 -maxrate 8M -bufsize 16M -vbaq 1 -preanalysis 1 -me full -maxaufsize 4 -gops_per_idr 45 -open_gop 1"

    # Streaming optimized - Low latency with good quality
    # Ideal for media servers (Plex, Jellyfin, Emby)
    ["streaming"]="-quality quality -rc vbr_latency -qvbr_quality_level 23 -maxrate 10M -bufsize 20M -vbaq 1 -preanalysis 1 -me quarter -maxaufsize 3 -gops_per_idr 60 -open_gop 1"
)

# VA-API presets for open-source driver path
declare -A VAAPI_QUALITY_PRESETS=(
    ["maxquality"]="-rc CQP -qp 18 -maxrate 50M -compression_level 7"
    ["balanced"]="-rc VBR -b:v 8M -maxrate 15M -compression_level 5 -qp 22"
    ["fast"]="-rc VBR -b:v 5M -maxrate 8M -compression_level 3"
    ["highcompression"]="-rc VBR -b:v 3M -maxrate 5M -compression_level 7 -qp 26"
    ["streaming"]="-rc VBR -b:v 8M -maxrate 10M -compression_level 5 -qp 23"
)

# Enhanced B-frame optimization settings per codec
# Increased reference frames for better temporal compression
declare -A BFRAME_SETTINGS=(
    ["h264"]="-bf 3 -refs 6 -b_strategy 2 -weightb 1 -directpred 3 -b_pyramid normal"
    ["hevc"]="-bf 5 -refs 5 -b_strategy 2 -weightb 1 -b_pyramid 1"
)

# Motion estimation settings per quality preset
# Enhanced for better motion handling
declare -A ME_SETTINGS=(
    ["maxquality"]="-me_method full -subq 7 -trellis 2 -cmp 2 -mbd 2 -flags +mv0 -flags2 +fastpskip"
    ["balanced"]="-me_method hex -subq 5 -trellis 1 -cmp 1 -mbd 1"
    ["fast"]="-me_method dia -subq 2 -trellis 0 -cmp 0 -mbd 0"
    ["highcompression"]="-me_method full -subq 6 -trellis 2 -cmp 2 -mbd 2"
    ["streaming"]="-me_method hex -subq 5 -trellis 1 -cmp 1 -mbd 1"
)

# Texture preservation settings
declare -A TEXTURE_SETTINGS=(
    ["preserve"]="-vbaq 1 -preanalysis 1 -qcomp 0.8 -psy-rd 1.0 -luma_adaptive_quantization 1"
    ["balanced"]="-vbaq 1 -preanalysis 1 -qcomp 0.7 -psy-rd 0.8"
    ["fast"]="-vbaq 0 -preanalysis 0 -qcomp 0.6"
)

# ============================================
# Utility Functions
# ============================================

print_banner() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                                   ║${NC}"
    echo -e "${CYAN}║   Advanced AMD GPU Batch Video Converter v${VERSION}                    ║${NC}"
    echo -e "${CYAN}║   Wael Isa - www.wael.name                                        ║${NC}"
    echo -e "${CYAN}║   GitHub: https://github.com/waelisa/ffmpeg-Batch-convert         ║${NC}"
    echo -e "${CYAN}║                                                                   ║${NC}"
    echo -e "${CYAN}║   Optimized for AMD Graphics Cards with:                          ║${NC}"
    echo -e "${CYAN}║   • Full hardware pipeline (decode → filter → encode)             ║${NC}"
    echo -e "${CYAN}║   • VBAQ (Variance Based Adaptive Quantization)                   ║${NC}"
    echo -e "${CYAN}║   • Pre-analysis for better quality distribution                  ║${NC}"
    echo -e "${CYAN}║   • Open GOP for improved compression                             ║${NC}"
    echo -e "${CYAN}║   • 6 Reference frames for better prediction                      ║${NC}"
    echo -e "${CYAN}║   • Peak bitrate control for consistent quality                   ║${NC}"
    echo -e "${CYAN}║   • Texture preservation for fine details                         ║${NC}"
    echo -e "${CYAN}║                                                                   ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
}

print_usage() {
    echo -e "${GREEN}USAGE:${NC}"
    echo -e "    $SCRIPT_NAME [OPTIONS] [FILES...]"
    echo
    echo -e "${GREEN}OPTIONS:${NC}"
    echo -e "    -h, --help              Show this help message"
    echo -e "    -v, --version           Show version information"
    echo -e "    -d, --debug             Enable debug output"
    echo -e "    --dry-run              Show commands without executing"
    echo -e "    --install-deps         Install required dependencies"
    echo -e "    --conf                 Interactive configuration menu"
    echo -e "    --save-conf NAME       Save current settings as profile"
    echo -e "    --load-conf NAME       Load profile"
    echo -e "    --list-conf            List available profiles"
    echo
    echo -e "${YELLOW}Output Options:${NC}"
    echo -e "    -o, --output DIR        Output directory (default: ./output)"
    echo -e "    -c, --codec CODEC       Video codec: h264, hevc (default: h264)"
    echo -e "    -p, --preset PRESET     Quality preset: "
    echo -e "                            • maxquality - Maximum quality (largest files)"
    echo -e "                            • balanced  - Good quality/size balance"
    echo -e "                            • fast      - Fastest encoding"
    echo -e "                            • highcompression - Smallest files"
    echo -e "                            • streaming - Optimized for media servers"
    echo -e "                            (default: balanced)"
    echo -e "    -q, --quality VAL       Quality override (16-32, lower = better)"
    echo -e "    -a, --audio-bitrate R   Audio bitrate (default: 128k)"
    echo -e "    -f, --format EXT        Output container (default: mp4)"
    echo -e "    -r, --resolution PRESET Resolution preset: 480p, 720p, 1080p, 2K, 4K, 8K"
    echo
    echo -e "${YELLOW}Processing Options:${NC}"
    echo -e "    --keep-tree             Preserve directory structure"
    echo -e "    --no-hwaccel            Disable hardware acceleration (CPU only)"
    echo -e "    --force                 Overwrite existing files"
    echo -e "    --no-vbaq               Disable Variance Based Adaptive Quantization"
    echo -e "    --no-preanalysis        Disable pre-analysis (faster but lower quality)"
    echo -e "    --no-opengop            Disable Open GOP (better compatibility)"
    echo -e "    --texture-preserve      Maximum texture detail preservation"
    echo -e "    --target-size SIZE      Target file size (e.g., 100M, 1G)"
    echo
    echo -e "${YELLOW}Filter Options:${NC}"
    echo -e "    --scale WxH             Scale video (e.g., 1920x1080, -1x720 for height 720)"
    echo -e "    --fps FPS               Set output framerate"
    echo -e "    --trim START:DURATION   Trim video (e.g., 00:01:00:30 for 1m30s)"
    echo -e "    --deinterlace           Enable deinterlacing"
    echo -e "    --denoise LEVEL         Apply denoising (low, medium, high)"
    echo -e "    --crop W:H:X:Y          Crop video (width:height:x:y)"
    echo
    echo -e "${GREEN}EXAMPLES:${NC}"
    echo -e "    # Basic conversion with auto hardware detection"
    echo -e "    $SCRIPT_NAME *.mkv"
    echo
    echo -e "    # Interactive configuration menu"
    echo -e "    $SCRIPT_NAME --conf"
    echo
    echo -e "    # Save and load profiles"
    echo -e "    $SCRIPT_NAME --save-conf myprofile --preset maxquality"
    echo -e "    $SCRIPT_NAME --load-conf myprofile *.mp4"
    echo
    echo -e "    # Maximum quality H.265 encoding with texture preservation"
    echo -e "    $SCRIPT_NAME -c hevc -p maxquality --texture-preserve -o archived/ video.mp4"
    echo
    echo -e "    # 4K conversion with streaming preset"
    echo -e "    $SCRIPT_NAME -r 4K -p streaming *.mkv"
    echo
    echo -e "${CYAN}AMD OPTIMIZATION NOTES:${NC}"
    echo -e "    • VBAQ improves quality in complex textures (grass, film grain)"
    echo -e "    • Open GOP allows frame references across scene cuts"
    echo -e "    • 6 reference frames provide better motion prediction"
    echo -e "    • Peak bitrate control prevents blocking in fast motion"
    echo -e "    • Texture preservation keeps fine details sharp"
    echo
    echo -e "${BLUE}Supported input formats:${NC} ${INPUT_EXTENSIONS[*]}"
}

print_version() {
    echo "Advanced AMD GPU Batch Video Converter v${VERSION}"
    echo "Wael Isa - www.wael.name"
    echo "GitHub: https://github.com/waelisa/ffmpeg-Batch-convert"
    echo "Optimized for AMD Graphics Cards"
}

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "INFO")    echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN")    echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR")   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        "DEBUG")   [[ "${DEBUG:-false}" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
        "AMD")     echo -e "${CYAN}[AMD]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        *)         echo "$message" ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
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
            # For Debian/Ubuntu, download the latest .deb
            local temp_dir=$(mktemp -d)
            cd "$temp_dir"
            wget -q "https://github.com/charmbracelet/gum/releases/download/v0.14.0/gum_0.14.0_amd64.deb"
            dpkg -i gum_0.14.0_amd64.deb
            apt-get install -f -y
            cd - > /dev/null
            rm -rf "$temp_dir"
            ;;
        dnf)
            # For Fedora/RHEL
            echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | tee /etc/yum.repos.d/charm.repo
            dnf install -y gum
            ;;
        pacman)
            # For Arch
            pacman -S --noconfirm gum
            ;;
        *)
            # Fallback: download binary directly
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

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Interactive Configuration Builder                     ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"

    # Codec selection
    CODEC=$(gum choose --header "Select video codec" "h264" "hevc" --selected "h264")

    # Preset selection
    PRESET=$(gum choose --header "Select quality preset" \
        "maxquality" "balanced" "fast" "highcompression" "streaming" --selected "balanced")

    # Resolution preset
    if gum confirm "Apply resolution preset?" --default=false; then
        local res=$(gum choose --header "Select resolution" \
            "480p" "720p" "1080p" "2K" "4K" "8K")
        SCALE="${RESOLUTION_PRESETS[$res]}"
    fi

    # Quality value
    if gum confirm "Custom quality value?" --default=false; then
        QUALITY_VAL=$(gum input --placeholder "Enter quality value (16-32, lower=better)" --value "22")
    fi

    # Audio bitrate
    AUDIO_BITRATE=$(gum input --placeholder "Audio bitrate (e.g., 128k)" --value "128k")

    # Advanced options
    if gum confirm "Configure advanced options?" --default=false; then
        echo -e "${YELLOW}Advanced Options:${NC}"

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

        if gum confirm "Target specific file size?" --default=false; then
            TARGET_SIZE=$(gum input --placeholder "Target size (e.g., 100M, 1G)")
        fi
    fi

    # Filter options
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

    # Output directory
    OUTPUT_DIR=$(gum input --placeholder "Output directory" --value "output")

    # Save configuration
    if gum confirm "Save this configuration as a profile?" --default=false; then
        local profile_name=$(gum input --placeholder "Profile name")
        save_configuration "$profile_name"
    fi

    # Show summary
    echo -e "\n${GREEN}Configuration Summary:${NC}"
    echo -e "  Codec: $CODEC"
    echo -e "  Preset: $PRESET"
    [[ -n "${SCALE:-}" ]] && echo -e "  Resolution: $SCALE"
    [[ -n "${QUALITY_VAL:-}" ]] && echo -e "  Quality: $QUALITY_VAL"
    echo -e "  Audio: $AUDIO_BITRATE"
    [[ "$NO_VBAQ" == "true" ]] && echo -e "  VBAQ: Disabled" || echo -e "  VBAQ: Enabled"
    [[ "$NO_PREANALYSIS" == "true" ]] && echo -e "  Pre-analysis: Disabled" || echo -e "  Pre-analysis: Enabled"
    [[ "$TEXTURE_PRESERVE" == "true" ]] && echo -e "  Texture Preservation: Enabled"

    if gum confirm "Start conversion with these settings?" --default=true; then
        # Continue to file selection
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
EOF

    log "SUCCESS" "Configuration saved to: $config_file"
}

load_configuration() {
    local profile_name="$1"
    local config_file="${PROFILES_DIR}/${profile_name}.conf"

    if [[ ! -f "$config_file" ]]; then
        # Try in script directory
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
    echo -e "${BLUE}Available Profiles:${NC}"

    # List profiles directory
    if [[ -d "$PROFILES_DIR" ]]; then
        for conf in "$PROFILES_DIR"/*.conf; do
            if [[ -f "$conf" ]]; then
                local name=$(basename "$conf" .conf)
                local preset=$(grep "^PRESET=" "$conf" | cut -d'"' -f2)
                local codec=$(grep "^CODEC=" "$conf" | cut -d'"' -f2)
                echo -e "  ${GREEN}•${NC} $name (${codec}/${preset})"
            fi
        done
    fi

    # List in current directory
    for conf in *.conf; do
        if [[ -f "$conf" ]] && [[ "$conf" != "ffmpeg-Batch-convert.conf" ]]; then
            local name=$(basename "$conf" .conf)
            local preset=$(grep "^PRESET=" "$conf" 2>/dev/null | cut -d'"' -f2)
            local codec=$(grep "^CODEC=" "$conf" 2>/dev/null | cut -d'"' -f2)
            echo -e "  ${GREEN}•${NC} $name (${codec}/${preset})"
        fi
    done
}

# ============================================
# Distribution Detection & Package Management
# ============================================

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
        ubuntu|debian|linuxmint|popos)
            echo "apt"
            ;;
        fedora|rhel|centos|almalinux|rocky)
            echo "dnf"
            ;;
        arch|manjaro|endeavouros)
            echo "pacman"
            ;;
        opensuse*|suse)
            echo "zypper"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

install_dependencies() {
    log "INFO" "Checking and installing dependencies..."

    # Check for required commands
    local missing_deps=()

    if ! check_command "ffmpeg"; then
        missing_deps+=("ffmpeg")
    fi

    if ! check_command "vainfo"; then
        missing_deps+=("vainfo")
    fi

    if ! check_command "lspci"; then
        missing_deps+=("pciutils")
    fi

    if ! check_command "gum"; then
        install_gum
    fi

    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        log "INFO" "All dependencies are already installed."
        return 0
    fi

    log "INFO" "Missing dependencies: ${missing_deps[*]}"

    # Detect distribution and install packages
    local distro=$(detect_distribution)
    local pkg_manager=$(get_package_manager "$distro")

    log "INFO" "Detected distribution: $distro"
    log "INFO" "Using package manager: $pkg_manager"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log "WARN" "Dependencies need to be installed, but script is not running as root."
        log "WARN" "Please run: sudo $0 --install-deps"
        return 1
    fi

    # Install packages based on distribution
    case "$pkg_manager" in
        apt)
            log "INFO" "Updating package lists..."
            apt update
            log "INFO" "Installing FFmpeg and VA-API packages..."
            apt install -y ffmpeg vainfo mesa-va-drivers \
                libva-drm2 libva-x11-2 va-driver-all \
                mesa-utils pciutils bc wget
            ;;

        dnf)
            log "INFO" "Installing FFmpeg and VA-API packages..."
            # Enable RPM Fusion if needed
            if ! rpm -q rpmfusion-free-release &>/dev/null; then
                dnf install -y https://download1.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm
            fi
            dnf install -y ffmpeg ffmpeg-libs vainfo \
                mesa-va-drivers libva-utils pciutils bc wget
            ;;

        pacman)
            log "INFO" "Installing FFmpeg and VA-API packages..."
            pacman -S --noconfirm ffmpeg libva-utils \
                mesa-utils libva-mesa-driver pciutils bc wget
            ;;

        zypper)
            log "INFO" "Installing FFmpeg and VA-API packages..."
            zypper install -y ffmpeg vainfo \
                libva-utils Mesa-dri pciutils bc wget
            ;;

        *)
            log "ERROR" "Unsupported distribution for automatic installation"
            return 1
            ;;
    esac

    log "INFO" "Dependencies installed successfully."
}

# ============================================
# Hardware Detection & Analysis
# ============================================

detect_amd_gpu() {
    if lspci | grep -i "vga.*amd" &>/dev/null || \
       lspci | grep -i "vga.*ati" &>/dev/null || \
       lspci | grep -i "display.*amd" &>/dev/null; then
        return 0
    fi
    return 1
}

get_amd_gpu_model() {
    lspci | grep -i "vga.*amd\|vga.*ati\|display.*amd" | \
        sed -E 's/.*: (.*)/\1/' | head -1
}

check_vaapi_support() {
    if check_command "vainfo"; then
        if vainfo 2>&1 | grep -q "VA-API"; then
            return 0
        fi
    fi
    return 1
}

check_amf_support() {
    # Check if AMF is available in FFmpeg
    if ffmpeg -encoders 2>/dev/null | grep -q "h264_amf"; then
        return 0
    fi
    return 1
}

get_vaapi_profiles() {
    if check_command "vainfo"; then
        vainfo 2>/dev/null | grep -E "VAProfile(H\|HEVC)" || true
    fi
}

get_render_device() {
    # Find the first AMD render device
    for device in /dev/dri/renderD*; do
        if [[ -e "$device" ]]; then
            # Check if it's an AMD device
            if udevadm info -a -n "$device" 2>/dev/null | grep -qi "amd\|ati"; then
                echo "$device"
                return 0
            fi
        fi
    done

    # Fallback to first render device
    for device in /dev/dri/renderD*; do
        if [[ -e "$device" ]]; then
            echo "$device"
            return 0
        fi
    done

    echo ""
}

detect_hardware_capabilities() {
    log "INFO" "Detecting hardware capabilities..."

    # Check for AMD GPU
    if detect_amd_gpu; then
        local gpu_model=$(get_amd_gpu_model)
        log "AMD" "AMD GPU detected: ${gpu_model:-Unknown model}"

        # Check for VA-API support
        if check_vaapi_support; then
            log "AMD" "✓ VA-API is supported"
            RENDER_DEVICE=$(get_render_device)
            [[ -n "$RENDER_DEVICE" ]] && log "AMD" "✓ Render device: $RENDER_DEVICE"
            HAS_VAAPI=true

            # Show supported profiles
            log "DEBUG" "Supported VA-API profiles:"
            get_vaapi_profiles | while read line; do
                log "DEBUG" "  $line"
            done
        else
            log "WARN" "VA-API not supported. Install mesa-va-drivers."
            HAS_VAAPI=false
        fi

        # Check for AMF support
        if check_amf_support; then
            log "AMD" "✓ AMF encoder is available (proprietary path)"
            HAS_AMF=true
        else
            log "DEBUG" "AMF not available, using VA-API (open source path)"
            HAS_AMF=false
        fi

        # Check for HEVC hardware support
        if vainfo 2>/dev/null | grep -q "VAProfileHEVC"; then
            log "AMD" "✓ HEVC hardware encoding supported"
            HAS_HEVC_HW=true
        else
            log "DEBUG" "HEVC hardware encoding not available"
            HAS_HEVC_HW=false
        fi

        # Check for Open GOP support
        if ffmpeg -h encoder=h264_amf 2>&1 | grep -q "open_gop"; then
            log "AMD" "✓ Open GOP supported"
            HAS_OPEN_GOP=true
        fi
    else
        log "WARN" "No AMD GPU detected. Falling back to CPU encoding."
        HAS_AMD=false
        HAS_VAAPI=false
        HAS_AMF=false
    fi
}

# ============================================
# FFmpeg Command Generation with Enhanced AMD Optimizations
# ============================================

calculate_bitrate_for_target_size() {
    local input_file="$1"
    local target_size="$2"
    local duration

    # Get duration in seconds
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null)

    if [[ -n "$duration" ]] && [[ -n "$target_size" ]]; then
        # Convert target size to bits
        local size_num="${target_size%[a-zA-Z]}"
        local size_unit="${target_size//[0-9.]/}"

        case "${size_unit^^}" in
            "K"|"KB") target_bits=$(echo "$size_num * 1024 * 8" | bc) ;;
            "M"|"MB") target_bits=$(echo "$size_num * 1024 * 1024 * 8" | bc) ;;
            "G"|"GB") target_bits=$(echo "$size_num * 1024 * 1024 * 1024 * 8" | bc) ;;
            *) target_bits=$(echo "$size_num * 1024 * 1024 * 8" | bc) ;; # Default to MB
        esac

        # Calculate bitrate (bits per second)
        local bitrate=$(echo "$target_bits / $duration" | bc)

        # Convert to kbps and round
        echo $(echo "$bitrate / 1024" | bc)
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

build_ffmpeg_command() {
    local input_file="$1"
    local output_file="$2"
    local cmd="ffmpeg"

    # Add log level (reduce verbosity unless debug)
    if [[ "${DEBUG:-false}" != "true" ]]; then
        cmd+=" -loglevel error -stats"
    fi

    # Handle target file size if specified
    if [[ -n "${TARGET_SIZE:-}" ]]; then
        local calculated_bitrate=$(calculate_bitrate_for_target_size "$input_file" "$TARGET_SIZE")
        if [[ -n "$calculated_bitrate" ]]; then
            log "INFO" "Target size: $TARGET_SIZE, calculated bitrate: ${calculated_bitrate}k"
            # Override quality settings for target size
            USE_TARGET_BITRATE=true
            TARGET_VIDEO_BITRATE="$calculated_bitrate"
        fi
    fi

    # Hardware acceleration setup
    if [[ "${NO_HWACCEL:-false}" != "true" ]] && [[ "$HAS_VAAPI" == "true" ]]; then
        local driver_info=$(get_amd_driver_info)
        log "DEBUG" "Using AMD driver: $driver_info"

        if [[ "$USE_AMF" == "true" ]] && [[ "$HAS_AMF" == "true" ]] && [[ "$CODEC" == "h264" ]]; then
            # AMF encoding path (proprietary, better quality)
            log "AMD" "Using AMF hardware encoding pipeline"
            cmd+=" -hwaccel vaapi -hwaccel_device $RENDER_DEVICE -hwaccel_output_format vaapi"
            cmd+=" -i \"$input_file\""

            # Video encoder with AMD optimizations
            cmd+=" -c:v ${CODEC}_amf"

            # Apply quality preset or target bitrate
            if [[ "${USE_TARGET_BITRATE:-false}" == "true" ]]; then
                # Use target bitrate mode
                cmd+=" -rc vbr_peak -b:v ${TARGET_VIDEO_BITRATE}k -maxrate $((TARGET_VIDEO_BITRATE * 2))k -bufsize $((TARGET_VIDEO_BITRATE * 4))k"
            elif [[ -n "${QUALITY_PRESETS[$PRESET]:-}" ]]; then
                cmd+=" ${QUALITY_PRESETS[$PRESET]}"
            fi

            # Override quality if specified
            if [[ -n "${QUALITY_VAL:-}" ]] && [[ "${USE_TARGET_BITRATE:-false}" != "true" ]]; then
                if [[ "$PRESET" == "maxquality" ]] || [[ "$PRESET" == "cqp"* ]]; then
                    cmd+=" -qp_i $QUALITY_VAL -qp_p $QUALITY_VAL -qp_b $((QUALITY_VAL + 2))"
                else
                    cmd+=" -qvbr_quality_level $QUALITY_VAL"
                fi
            fi

            # Apply texture preservation if requested
            if [[ "${TEXTURE_PRESERVE:-false}" == "true" ]]; then
                cmd+=" ${TEXTURE_SETTINGS[preserve]}"
            fi

            # Disable VBAQ if requested
            if [[ "${NO_VBAQ:-false}" == "true" ]]; then
                cmd=${cmd/"-vbaq 1"/"-vbaq 0"}
            fi

            # Disable preanalysis if requested
            if [[ "${NO_PREANALYSIS:-false}" == "true" ]]; then
                cmd=${cmd/"-preanalysis 1"/"-preanalysis 0"}
            fi

            # Disable Open GOP if requested
            if [[ "${NO_OPENGOP:-false}" == "true" ]]; then
                cmd=${cmd/"-open_gop 1"/"-open_gop 0"}
            fi
        else
            # VA-API encoding path (open source, good compatibility)
            log "AMD" "Using VA-API hardware encoding pipeline"
            cmd+=" -hwaccel vaapi -hwaccel_device $RENDER_DEVICE -hwaccel_output_format vaapi"
            cmd+=" -i \"$input_file\""

            # Build video filter chain
            local filters="format=nv12,hwupload"

            # Add deinterlacing if requested
            if [[ "${DEINTERLACE:-false}" == "true" ]]; then
                filters="deinterlace_vaapi,$filters"
            fi

            # Add denoising if requested
            if [[ -n "${DENOISE:-}" ]]; then
                case "$DENOISE" in
                    low)    filters="denoise_vaapi=level=4,$filters" ;;
                    medium) filters="denoise_vaapi=level=8,$filters" ;;
                    high)   filters="denoise_vaapi=level=16,$filters" ;;
                esac
            fi

            # Add scaling if requested
            if [[ -n "${SCALE:-}" ]]; then
                filters="scale_vaapi=$SCALE,$filters"
            fi

            # Add cropping if requested
            if [[ -n "${CROP:-}" ]]; then
                filters="crop_vaapi=$CROP,$filters"
            fi

            # Add framerate if requested
            if [[ -n "${FPS:-}" ]]; then
                filters="fps=$FPS,$filters"
            fi

            cmd+=" -vf \"$filters\""
            cmd+=" -c:v ${CODEC}_vaapi"

            # Apply VA-API quality preset
            if [[ -n "${VAAPI_QUALITY_PRESETS[$PRESET]:-}" ]]; then
                cmd+=" ${VAAPI_QUALITY_PRESETS[$PRESET]}"
            fi

            # Override with target bitrate if specified
            if [[ "${USE_TARGET_BITRATE:-false}" == "true" ]]; then
                cmd+=" -b:v ${TARGET_VIDEO_BITRATE}k"
            fi
        fi

        # Add B-frame optimizations
        if [[ -n "${BFRAME_SETTINGS[$CODEC]:-}" ]]; then
            cmd+=" ${BFRAME_SETTINGS[$CODEC]}"
        fi

        # Add motion estimation optimizations
        if [[ -n "${ME_SETTINGS[$PRESET]:-}" ]]; then
            cmd+=" ${ME_SETTINGS[$PRESET]}"
        fi
    else
        # CPU encoding fallback with optimizations
        log "INFO" "Using CPU encoding"
        cmd+=" -i \"$input_file\""
        cmd+=" -c:v libx${CODEC}"

        # Apply CRF for CPU encoding
        if [[ -n "${QUALITY_VAL:-}" ]]; then
            cmd+=" -crf $QUALITY_VAL"
        else
            case "$PRESET" in
                maxquality)      cmd+=" -crf 16 -preset slow" ;;
                balanced)        cmd+=" -crf 22 -preset medium" ;;
                fast)            cmd+=" -crf 26 -preset fast" ;;
                highcompression) cmd+=" -crf 28 -preset veryslow" ;;
                streaming)       cmd+=" -crf 23 -preset medium" ;;
            esac
        fi

        # Add CPU optimizations
        cmd+=" -tune film -profile:v high -level 4.1"

        # Add B-frame settings for CPU
        if [[ -n "${BFRAME_SETTINGS[$CODEC]:-}" ]]; then
            cmd+=" ${BFRAME_SETTINGS[$CODEC]}"
        fi

        # Override with target bitrate if specified
        if [[ "${USE_TARGET_BITRATE:-false}" == "true" ]]; then
            cmd+=" -b:v ${TARGET_VIDEO_BITRATE}k"
        fi
    fi

    # Audio encoding
    cmd+=" -c:a aac -b:a $AUDIO_BITRATE"

    # Add trim if requested
    if [[ -n "${TRIM:-}" ]]; then
        cmd+=" -ss ${TRIM%:*} -t ${TRIM#*:}"
    fi

    # Add faststart for web optimization
    cmd+=" -movflags +faststart"

    # Add metadata preservation
    cmd+=" -map_metadata 0"

    # Output file
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
            -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null)
        local video_codec=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null)
        local resolution=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=width,height -of csv=p=0 "$input_file" 2>/dev/null)
        local bitrate=$(ffprobe -v error -show_entries format=bit_rate \
            -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null)

        if [[ -n "$duration" ]] && [[ -n "$video_codec" ]]; then
            log "INFO" "Input: ${video_codec} | ${resolution} | $(printf "%.2f" $duration)s | ${bitrate}bps"
        fi
    fi
}

process_file() {
    local input_file="$1"
    local output_subdir="$OUTPUT_DIR"

    # Check if file exists
    if [[ ! -f "$input_file" ]]; then
        log "WARN" "Skipping non-existent file: $input_file"
        return
    fi

    # Handle directory structure preservation
    if [[ "${KEEP_TREE:-false}" == "true" ]]; then
        local rel_path="${input_file#./}"
        output_subdir="$OUTPUT_DIR/$(dirname "$rel_path")"
    fi

    # Create output directory
    mkdir -p "$output_subdir"

    # Generate output filename
    local basename=$(basename "$input_file")
    local filename="${basename%.*}"
    local output_file="$output_subdir/${filename}.${CONTAINER}"

    # Check if output already exists
    if [[ -f "$output_file" ]] && [[ "${FORCE:-false}" != "true" ]]; then
        log "WARN" "Output file exists, skipping (use --force to overwrite): $output_file"
        return
    fi

    log "INFO" "Processing: $input_file"
    get_file_info "$input_file"
    log "INFO" "Output: $output_file"

    # Build FFmpeg command
    local cmd=$(build_ffmpeg_command "$input_file" "$output_file")

    # Dry run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} $cmd"
        return
    fi

    # Execute conversion
    log "DEBUG" "Running: $cmd"

    # Use eval to handle complex quoting
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log "SUCCESS" "✓ Successfully converted: $input_file"
        # Show output file size
        if [[ -f "$output_file" ]]; then
            local size=$(du -h "$output_file" | cut -f1)
            log "INFO" "  Output size: $size"

            # Calculate compression ratio if possible
            local input_size=$(du -b "$input_file" | cut -f1)
            local output_size=$(du -b "$output_file" | cut -f1)
            if [[ -n "$input_size" ]] && [[ -n "$output_size" ]] && [[ $input_size -gt 0 ]]; then
                local ratio=$(echo "scale=2; $output_size * 100 / $input_size" | bc)
                log "INFO" "  Compression: ${ratio}% of original"
            fi
        fi
    else
        log "ERROR" "✗ Failed to convert: $input_file"
        return 1
    fi
}

process_files() {
    local files=("$@")

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Process files
    log "INFO" "Found ${#files[@]} files to process"

    local success_count=0
    local fail_count=0
    local start_time=$(date +%s)

    for file in "${files[@]}"; do
        echo "-----------------------------------"
        if process_file "$file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done

    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    local minutes=$((total_time / 60))
    local seconds=$((total_time % 60))

    # Summary
    echo "==================================="
    log "INFO" "=== Conversion Complete ==="
    log "SUCCESS" "Successful: $success_count"
    [[ $fail_count -gt 0 ]] && log "ERROR" "Failed: $fail_count"
    log "INFO" "Total time: ${minutes}m ${seconds}s"
    log "INFO" "Log file: $LOG_FILE"
    echo "==================================="
}

# ============================================
# Main Script
# ============================================

main() {
    # Parse command line arguments
    local files=()

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
            --install-deps)
                install_dependencies
                exit $?
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                files+=("$1")
                shift
                ;;
        esac
    done

    # Print banner
    print_banner

    # Set defaults
    CODEC="${CODEC:-$DEFAULT_CODEC}"
    PRESET="${PRESET:-$DEFAULT_QUALITY}"
    AUDIO_BITRATE="${AUDIO_BITRATE:-$DEFAULT_AUDIO_BITRATE}"
    CONTAINER="${CONTAINER:-$DEFAULT_CONTAINER}"

    # Validate codec
    if [[ "$CODEC" != "h264" ]] && [[ "$CODEC" != "hevc" ]]; then
        log "ERROR" "Invalid codec: $CODEC (must be h264 or hevc)"
        exit 1
    fi

    # Validate preset
    if [[ -z "${QUALITY_PRESETS[$PRESET]:-}" ]] && [[ -z "${VAAPI_QUALITY_PRESETS[$PRESET]:-}" ]]; then
        log "ERROR" "Invalid preset: $PRESET"
        echo "Valid presets: ${!QUALITY_PRESETS[*]}"
        exit 1
    fi

    # Validate denoise level
    if [[ -n "${DENOISE:-}" ]]; then
        case "$DENOISE" in
            low|medium|high) ;;
            *)
                log "ERROR" "Invalid denoise level: $DENOISE (must be low, medium, or high)"
                exit 1
                ;;
        esac
    fi

    # Validate quality value
    if [[ -n "${QUALITY_VAL:-}" ]]; then
        if [[ "$QUALITY_VAL" -lt 16 ]] || [[ "$QUALITY_VAL" -gt 32 ]]; then
            log "WARN" "Quality value $QUALITY_VAL is outside recommended range (16-32)"
        fi
    fi

    # Create log file
    touch "$LOG_FILE"
    log "INFO" "=== Starting AMD GPU Batch Conversion v${VERSION} ==="
    log "INFO" "Log file: $LOG_FILE"

    # Check if files were provided
    if [[ ${#files[@]} -eq 0 ]]; then
        # If no files specified, process all supported files in current directory
        for ext in "${INPUT_EXTENSIONS[@]}"; do
            for file in *."$ext"; do
                [[ -f "$file" ]] && files+=("$file")
            done
        done
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        log "ERROR" "No input files found"
        print_usage
        exit 1
    fi

    # Check for FFmpeg
    if ! check_command "ffmpeg"; then
        log "WARN" "FFmpeg not found. Attempting to install dependencies..."
        install_dependencies

        if ! check_command "ffmpeg"; then
            log "ERROR" "FFmpeg installation failed. Please install manually."
            exit 1
        fi
    fi

    # Detect hardware
    detect_hardware_capabilities

    # Determine encoding method
    if [[ "$NO_HWACCEL" == "true" ]]; then
        USE_AMF=false
        log "INFO" "Hardware acceleration disabled, using CPU encoding"
    elif [[ "$HAS_AMF" == "true" ]] && [[ "$CODEC" == "h264" ]]; then
        USE_AMF=true
        log "AMD" "Using AMF hardware encoding (proprietary driver path)"
    elif [[ "$HAS_VAAPI" == "true" ]]; then
        USE_AMF=false
        log "AMD" "Using VA-API hardware encoding (open source driver path)"

        # Check HEVC support
        if [[ "$CODEC" == "hevc" ]] && [[ "$HAS_HEVC_HW" != "true" ]]; then
            log "WARN" "HEVC hardware encoding not supported, falling back to H.264"
            CODEC="h264"
        fi
    else
        USE_AMF=false
        log "WARN" "No hardware acceleration available, falling back to CPU encoding"
    fi

    # Show encoding settings
    log "INFO" "Encoding settings:"
    log "INFO" "  • Codec: $CODEC"
    log "INFO" "  • Preset: $PRESET"
    [[ -n "${QUALITY_VAL:-}" ]] && log "INFO" "  • Quality: $QUALITY_VAL"
    [[ -n "${SCALE:-}" ]] && log "INFO" "  • Resolution: $SCALE"
    [[ -n "${TARGET_SIZE:-}" ]] && log "INFO" "  • Target size: $TARGET_SIZE"
    log "INFO" "  • Audio bitrate: $AUDIO_BITRATE"
    [[ "$NO_VBAQ" == "true" ]] && log "INFO" "  • VBAQ: Disabled" || [[ -n "${NO_VBAQ:-}" ]] && log "INFO" "  • VBAQ: Enabled"
    [[ "$NO_PREANALYSIS" == "true" ]] && log "INFO" "  • Pre-analysis: Disabled" || [[ -n "${NO_PREANALYSIS:-}" ]] && log "INFO" "  • Pre-analysis: Enabled"
    [[ "$NO_OPENGOP" == "true" ]] && log "INFO" "  • Open GOP: Disabled" || [[ -n "${NO_OPENGOP:-}" ]] && log "INFO" "  • Open GOP: Enabled"
    [[ "$TEXTURE_PRESERVE" == "true" ]] && log "INFO" "  • Texture preservation: Enabled"

    # Process files
    process_files "${files[@]}"

    if [[ $fail_count -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
