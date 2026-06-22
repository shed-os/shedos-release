#!/usr/bin/env bash
# ShedOS ISO Test Script
# Tests the ISO in QEMU

set -euo pipefail

# Colors
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default settings
RAM="8G"   # Calamares requires >=6 GiB; 4G trips the welcome-screen RAM gate
CPUS="4"
DISK_SIZE="50G"
BOOT_MODE="uefi"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/out"
TEST_DIR="$PROJECT_DIR/test"

# OVMF paths (Arch Linux) - separate CODE and VARS for proper boot control
OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_CODE_SECBOOT="/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"

# --secureboot: boot the SB-enforcing firmware from the stock (Setup Mode) VARS
# and attach an emulated TPM2, so the installer's SB enrollment + `shedman tpm2`
# /`secureboot` verbs run against real measured-boot firmware. Off by default.
SECUREBOOT=false
TPM_DIR=""
SWTPM_PID=""

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

check_dependencies() {
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        log_error "qemu-system-x86_64 not found. Install: pacman -S qemu-full"
        exit 1
    fi

    if [[ "$BOOT_MODE" == "uefi" ]]; then
        if [[ ! -f "$OVMF_CODE" ]]; then
            log_error "OVMF_CODE not found. Install: pacman -S edk2-ovmf"
            exit 1
        fi
        if [[ ! -f "$OVMF_VARS" ]]; then
            log_error "OVMF_VARS not found. Install: pacman -S edk2-ovmf"
            exit 1
        fi
    fi

    if [[ "$SECUREBOOT" == true ]]; then
        if [[ "$BOOT_MODE" != "uefi" ]]; then
            log_error "--secureboot needs UEFI (Secure Boot is a UEFI feature)"
            exit 1
        fi
        if [[ ! -f "$OVMF_CODE_SECBOOT" ]]; then
            log_error "Secure Boot firmware not found: $OVMF_CODE_SECBOOT (pacman -S edk2-ovmf)"
            exit 1
        fi
        if ! command -v swtpm &>/dev/null; then
            log_error "swtpm not found — the TPM2 unlock proof needs it. Install: pacman -S swtpm"
            exit 1
        fi
    fi
}

# Emulated TPM2 backing the measured-boot unlock. State persists under test/tpm
# (cleared by --clean) so a TPM2-sealed key survives reboots; killed on exit.
start_swtpm() {
    TPM_DIR="$TEST_DIR/tpm"
    mkdir -p "$TPM_DIR"
    log_info "Starting emulated TPM2 (swtpm)..."
    swtpm socket --tpm2 --tpmstate "dir=$TPM_DIR" \
        --ctrl "type=unixio,path=$TPM_DIR/swtpm-sock" \
        --flags startup-clear --daemon --pid "file=$TPM_DIR/swtpm.pid"
    local i=0
    while [[ ! -S "$TPM_DIR/swtpm-sock" && $i -lt 50 ]]; do sleep 0.1; i=$((i+1)); done
    [[ -f "$TPM_DIR/swtpm.pid" ]] && SWTPM_PID=$(cat "$TPM_DIR/swtpm.pid")
}
stop_swtpm() {
    [[ -n "$SWTPM_PID" ]] && kill "$SWTPM_PID" 2>/dev/null
    SWTPM_PID=""
}
trap stop_swtpm EXIT INT TERM

# Firmware + TPM QEMU args for the given VARS file. Secure Boot needs SMM and a
# write-protected pflash, else the firmware will not enforce signatures.
FW_ARGS=()
TPM_QEMU_ARGS=()
build_fw_args() {
    local vars_path="$1"
    if [[ "$SECUREBOOT" == true ]]; then
        FW_ARGS=(
            -machine "q35,smm=on,accel=kvm"
            -global "driver=cfi.pflash01,property=secure,value=on"
            -global "ICH9-LPC.disable_s3=1"
            -drive "if=pflash,unit=0,format=raw,readonly=on,file=$OVMF_CODE_SECBOOT"
            -drive "if=pflash,unit=1,format=raw,file=$vars_path"
        )
        TPM_QEMU_ARGS=(
            -chardev "socket,id=chrtpm,path=$TPM_DIR/swtpm-sock"
            -tpmdev "emulator,id=tpm0,chardev=chrtpm"
            -device "tpm-crb,tpmdev=tpm0"
        )
    else
        FW_ARGS=(
            -machine "q35,accel=kvm"
            -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
            -drive "if=pflash,format=raw,file=$vars_path"
        )
        TPM_QEMU_ARGS=()
    fi
}

setup_ovmf_vars() {
    local vars_path="$TEST_DIR/OVMF_VARS.fd"
    local reset_flag="${1:-}"

    # Copy fresh VARS file for clean NVRAM state (ensures ISO boots first)
    if [[ ! -f "$vars_path" ]] || [[ "$reset_flag" == "reset" ]]; then
        log_info "Setting up fresh UEFI NVRAM..."
        cp "$OVMF_VARS" "$vars_path"
    fi

    echo "$vars_path"
}

# Pick a graphical display + virtio GPU from what QEMU actually has. Arch
# ships these as separate modules: GTK in qemu-ui-gtk, the virtio display
# devices in qemu-hw-display-virtio-*. qemu-base alone has neither, so fail
# loud with the exact package instead of QEMU's opaque "not a valid device
# model name" / "gtk is not a valid display". Use virgl GL only when a *-gl
# device is actually present; the ShedOS desktop needs a virtio GPU (DRM), so
# the built-in VGA/cirrus framebuffers won't run it.
DISPLAY_ARGS=()
VGA_ARGS=()
select_display() {
    local backends devices
    backends=$(qemu-system-x86_64 -display help 2>/dev/null)
    devices=$(qemu-system-x86_64 -device help 2>&1)
    if ! grep -qw gtk <<<"$backends"; then
        log_error "QEMU has no GTK display backend. Install: sudo pacman -S qemu-ui-gtk"
        exit 1
    fi
    if grep -q '"virtio-vga-gl"' <<<"$devices" && pacman -Q virglrenderer &>/dev/null; then
        VGA_ARGS=(-device virtio-vga-gl); DISPLAY_ARGS=(-display "gtk,gl=on")
    elif grep -q '"virtio-vga"' <<<"$devices"; then
        VGA_ARGS=(-device virtio-vga); DISPLAY_ARGS=(-display gtk)
    elif grep -q '"virtio-gpu-pci-gl"' <<<"$devices" && pacman -Q virglrenderer &>/dev/null; then
        VGA_ARGS=(-device virtio-gpu-pci-gl); DISPLAY_ARGS=(-display "gtk,gl=on")
    elif grep -q '"virtio-gpu-pci"' <<<"$devices"; then
        VGA_ARGS=(-device virtio-gpu-pci); DISPLAY_ARGS=(-display gtk)
    else
        log_error "QEMU has no virtio GPU device — the ShedOS desktop needs one."
        log_error "Arch splits these into modules that don't pull each other. Install the chain:"
        log_error "  sudo pacman -S qemu-hw-display-virtio-{gpu,gpu-gl,vga,vga-gl}"
        exit 1
    fi
}

find_iso() {
    local iso_path="${1:-}"

    if [[ -n "$iso_path" && -f "$iso_path" ]]; then
        echo "$iso_path"
        return
    fi

    # Find latest ISO in output directory
    local latest_iso
    latest_iso=$(ls -t "$OUTPUT_DIR"/*.iso 2>/dev/null | head -1)

    if [[ -z "$latest_iso" ]]; then
        log_error "No ISO found in $OUTPUT_DIR"
        exit 1
    fi

    echo "$latest_iso"
}

create_test_disk() {
    mkdir -p "$TEST_DIR"
    local disk_path="$TEST_DIR/test-disk.qcow2"

    if [[ ! -f "$disk_path" ]]; then
        log_info "Creating test disk ($DISK_SIZE)..."
        qemu-img create -f qcow2 "$disk_path" "$DISK_SIZE" >&2
    fi

    echo "$disk_path"
}

run_qemu_uefi() {
    local iso_path="$1"
    local disk_path="$2"
    local boot_from_disk="${3:-false}"
    local reset_nvram="${4:-false}"

    # Setup OVMF VARS (NVRAM)
    local vars_path
    if [[ "$reset_nvram" == "true" ]] || [[ "$boot_from_disk" != "true" ]]; then
        vars_path=$(setup_ovmf_vars "reset")
    else
        vars_path=$(setup_ovmf_vars)
    fi

    # start_swtpm sets TPM_DIR + creates the socket; build_fw_args reads TPM_DIR
    # to wire -chardev at it, so swtpm must come first.
    [[ "$SECUREBOOT" == true ]] && start_swtpm
    build_fw_args "$vars_path"

    if [[ "$boot_from_disk" == "true" ]]; then
        log_info "Starting QEMU in UEFI mode (booting from installed disk)..."
        qemu-system-x86_64 \
            -enable-kvm \
            "${FW_ARGS[@]}" \
            -cpu host \
            -m "$RAM" \
            -smp "$CPUS" \
            "${TPM_QEMU_ARGS[@]}" \
            -drive file="$disk_path",format=qcow2,if=virtio \
            -netdev user,id=net0,hostfwd=tcp::2222-:22 \
            -device virtio-net-pci,netdev=net0 \
            "${VGA_ARGS[@]}" \
            "${DISPLAY_ARGS[@]}" \
            -serial stdio \
            -usb \
            -device usb-tablet \
            -name "ShedOS Installed (UEFI)"
    else
        log_info "Starting QEMU in UEFI mode (booting from ISO)..."
        qemu-system-x86_64 \
            -enable-kvm \
            "${FW_ARGS[@]}" \
            -cpu host \
            -m "$RAM" \
            -smp "$CPUS" \
            "${TPM_QEMU_ARGS[@]}" \
            -drive file="$iso_path",media=cdrom,index=0 \
            -drive file="$disk_path",format=qcow2,if=virtio \
            -boot menu=on \
            -netdev user,id=net0,hostfwd=tcp::2222-:22 \
            -device virtio-net-pci,netdev=net0 \
            "${VGA_ARGS[@]}" \
            "${DISPLAY_ARGS[@]}" \
            -serial stdio \
            -usb \
            -device usb-tablet \
            -name "ShedOS Test (UEFI)"
    fi
}

run_qemu_bios() {
    local iso_path="$1"
    local disk_path="$2"

    log_info "Starting QEMU in BIOS mode..."

    qemu-system-x86_64 \
        -enable-kvm \
        -machine pc,accel=kvm \
        -cpu host \
        -m "$RAM" \
        -smp "$CPUS" \
        -drive file="$iso_path",media=cdrom,index=0 \
        -drive file="$disk_path",format=qcow2,if=virtio \
        -boot d \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        "${VGA_ARGS[@]}" \
        "${DISPLAY_ARGS[@]}" \
        -serial stdio \
        -usb \
        -device usb-tablet \
        -name "ShedOS Test (BIOS)"
}

show_help() {
    echo "ShedOS ISO Test Script"
    echo ""
    echo "Usage: $0 [ISO_PATH] [BOOT_MODE]"
    echo ""
    echo "Arguments:"
    echo "  ISO_PATH    Path to ISO file (default: latest in out/)"
    echo "  BOOT_MODE   uefi or bios (default: uefi)"
    echo ""
    echo "Options:"
    echo "  --ram SIZE      RAM size (default: 8G)"
    echo "  --cpus NUM      Number of CPUs (default: 4)"
    echo "  --disk SIZE     Test disk size (default: 50G)"
    echo "  --clean         Remove test disk before starting"
    echo "  --disk-only     Boot from installed disk (no ISO)"
    echo "  --secureboot    SB-enforcing firmware (Setup Mode) + emulated TPM2"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          # Test latest ISO in UEFI mode"
    echo "  $0 shedos.iso bios          # Test specific ISO in BIOS mode"
    echo "  $0 --ram 8G --cpus 8        # Test with more resources"
    echo "  $0 --disk-only              # Boot installed system"
}

main() {
    local iso_path=""
    local clean=false
    local disk_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ram)
                RAM="$2"
                shift 2
                ;;
            --cpus)
                CPUS="$2"
                shift 2
                ;;
            --disk)
                DISK_SIZE="$2"
                shift 2
                ;;
            --clean)
                clean=true
                shift
                ;;
            --disk-only)
                disk_only=true
                shift
                ;;
            --secureboot)
                SECUREBOOT=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            uefi|bios)
                BOOT_MODE="$1"
                shift
                ;;
            *)
                if [[ -z "$iso_path" ]]; then
                    iso_path="$1"
                fi
                shift
                ;;
        esac
    done

    check_dependencies
    select_display

    if [[ "$clean" == true ]]; then
        rm -rf "$TEST_DIR"
    fi

    local disk_path
    disk_path=$(create_test_disk)

    if [[ "$disk_only" == "true" ]]; then
        if [[ ! -f "$disk_path" ]]; then
            log_error "No test disk found. Run 'make test' first to install."
            exit 1
        fi
        log_info "Booting from installed disk..."
        run_qemu_uefi "" "$disk_path" "true"
    else
        iso_path=$(find_iso "$iso_path")
        log_info "Testing ISO: $iso_path"

        case "$BOOT_MODE" in
            uefi)
                run_qemu_uefi "$iso_path" "$disk_path" "false"
                ;;
            bios)
                run_qemu_bios "$iso_path" "$disk_path"
                ;;
            *)
                log_error "Invalid boot mode: $BOOT_MODE"
                exit 1
                ;;
        esac
    fi
}

main "$@"
