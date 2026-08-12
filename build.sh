#!/usr/bin/env bash
# ============================================================================
#  Cr-Tucana Kernel Build Script for Xiaomi Mi Note 10 (tucana)
#  Kernel: Linux 4.14 (arm64 / sm6150)
#  Toolchain: Neutron Clang
# ============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
#  Color definitions
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────
#  Path configurations
# ─────────────────────────────────────────────────────────────────────────────
# Kernel source root (directory where this script lives)
KERNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Neutron Clang toolchain
CLANG_DIR="/home/mik/xMik-Project/toolchains/neutron-clang"
CLANG_BIN="${CLANG_DIR}/bin"

# AnyKernel3 directory (for flashable zip packaging)
ANYKERNEL_DIR="${KERNEL_DIR}/tools/AnyKernel3"

# Output directory (out-of-tree build to keep source clean)
OUT_DIR="${KERNEL_DIR}/out"

# ─────────────────────────────────────────────────────────────────────────────
#  Build configurations
# ─────────────────────────────────────────────────────────────────────────────
# Defconfig
DEFCONFIG="tucana_defconfig"

# Architecture
ARCH="arm64"

# Target kernel image (Usually Image.gz-dtb or Image.gz for sm6150)
KERNEL_IMAGE="Image.gz-dtb"

# Number of parallel jobs
JOBS="$(nproc --all)"

# Zip output directory
ZIP_DIR="${KERNEL_DIR}/out/zip"

# ─────────────────────────────────────────────────────────────────────────────
#  Clang/LLVM tool variables
# ─────────────────────────────────────────────────────────────────────────────
export PATH="${CLANG_BIN}:${PATH}"
export ARCH="${ARCH}"
export SUBARCH="${ARCH}"
export KBUILD_BUILD_USER="xMikkkaa"

# ─────────────────────────────────────────────────────────────────────────────
#  Compiler Detection & Make arguments
# ─────────────────────────────────────────────────────────────────────────────
if command -v ccache &> /dev/null; then
    CC_CMD="ccache clang"
    CXX_CMD="ccache clang++"
else
    CC_CMD="clang"
    CXX_CMD="clang++"
fi

MAKE_ARGS=(
    O="${OUT_DIR}"
    ARCH="${ARCH}"
    SUBARCH="${ARCH}"
    LLVM=1
    LLVM_IAS=1
    CC="${CC_CMD}"
    HOSTCC="${CC_CMD}"
    HOSTCXX="${CXX_CMD}"
    LD="ld.lld"
    AR="llvm-ar"
    NM="llvm-nm"
    OBJCOPY="llvm-objcopy"
    OBJDUMP="llvm-objdump"
    STRIP="llvm-strip"
    OBJSIZE="llvm-size"
    READELF="llvm-readelf"
    CROSS_COMPILE="aarch64-linux-gnu-"
    CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
    CLANG_TRIPLE="aarch64-linux-gnu-"
    KCFLAGS="-Wno-error=fortify-source -Wno-error=sizeof-pointer-memaccess -Wno-error=strict-prototypes -Wno-enum-conversion -Wno-error=default-const-init-field-unsafe -Wno-default-const-init-field-unsafe"
)

# ─────────────────────────────────────────────────────────────────────────────
#  Helper functions
# ─────────────────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════${NC}"; \
                echo -e "${CYAN}${BOLD}  $*${NC}"; \
                echo -e "${CYAN}${BOLD}═══════════════════════════════════════════${NC}\n"; }

timer_start() { BUILD_START=$(date +"%s"); }
timer_end() {
    local BUILD_END=$(date +"%s")
    local DIFF=$((BUILD_END - BUILD_START))
    echo -e "\n${GREEN}${BOLD}⏱  Time elapsed: $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)${NC}\n"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Pre-flight checks
# ─────────────────────────────────────────────────────────────────────────────
preflight_check() {
    log_step "Pre-flight Checks"

    if [ ! -x "${CLANG_BIN}/clang" ]; then
        log_error "Clang not found at ${CLANG_BIN}/clang"
        exit 1
    fi

    local CLANG_VERSION
    CLANG_VERSION=$("${CLANG_BIN}/clang" --version | head -1)
    log_info "Clang: ${CLANG_VERSION}"

    if [ ! -e "${CLANG_BIN}/ld.lld" ]; then
        log_error "ld.lld not found at ${CLANG_BIN}/ld.lld"
        exit 1
    fi
    log_info "Linker: ld.lld (bundled with Neutron Clang)"

    if [ ! -d "${ANYKERNEL_DIR}" ]; then
        log_info "AnyKernel3 not found at ${ANYKERNEL_DIR}, attempting to clone..."
        git clone -q https://github.com/ghostrider-reborn/AnyKernel3 -b lisa "${ANYKERNEL_DIR}" || {
            log_error "Failed to clone AnyKernel3! Aborting..."
            exit 1
        }
        # Attempt to checkout tucana branch if it exists, matching build.sh behavior
        git -C "${ANYKERNEL_DIR}" checkout tucana &> /dev/null || true
    fi
    
    log_info "Device: Xiaomi Mi Note 10 (tucana / sm6150)"
    log_info "Target: ${KERNEL_IMAGE}"
    log_info "Jobs: ${JOBS}"

    log_success "All pre-flight checks passed!"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 1: Clean build (optional)
# ─────────────────────────────────────────────────────────────────────────────
clean_build() {
    log_step "Cleaning Build Directory"

    if [ -d "${OUT_DIR}" ]; then
        rm -rf "${OUT_DIR}"
        log_info "Removed existing output directory: ${OUT_DIR}"
    fi

    mkdir -p "${OUT_DIR}"
    log_success "Clean build directory created"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 2: Generate defconfig
# ─────────────────────────────────────────────────────────────────────────────
generate_defconfig() {
    log_step "Generating Defconfig"
    log_info "Merging configs: ${DEFCONFIG}"

    # For multiple configs, make sequentially processes them to merge correctly
    for cfg in ${DEFCONFIG}; do
        make -C "${KERNEL_DIR}" "${MAKE_ARGS[@]}" "${cfg}"
    done

    if [ ! -f "${OUT_DIR}/.config" ]; then
        log_error "Failed to generate .config"
        exit 1
    fi

    log_success "Defconfig generated successfully"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 3: Build kernel
# ─────────────────────────────────────────────────────────────────────────────
build_kernel() {
    log_step "Building Kernel (${KERNEL_IMAGE})"
    
    if [ -f "${OUT_DIR}/.version" ]; then
        rm "${OUT_DIR}/.version"
    fi

    timer_start

    make -C "${KERNEL_DIR}" "${MAKE_ARGS[@]}" -j"${JOBS}" "${KERNEL_IMAGE}" 2>&1 | tee "${OUT_DIR}/build.log"

    if [ ! -f "${OUT_DIR}/arch/${ARCH}/boot/${KERNEL_IMAGE}" ]; then
        log_error "Kernel image not found: ${OUT_DIR}/arch/${ARCH}/boot/${KERNEL_IMAGE}"
        log_error "Build failed! Check ${OUT_DIR}/build.log for details."
        exit 1
    fi

    timer_end

    local IMG_SIZE
    IMG_SIZE=$(du -h "${OUT_DIR}/arch/${ARCH}/boot/${KERNEL_IMAGE}" | awk '{print $1}')
    log_success "Kernel built successfully!"
    log_info "Image: ${OUT_DIR}/arch/${ARCH}/boot/${KERNEL_IMAGE} (${IMG_SIZE})"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 4: Package with AnyKernel3
# ─────────────────────────────────────────────────────────────────────────────
package_zip() {
    log_step "Packaging Flashable Zip with AnyKernel3"

    local STAGING_DIR="${OUT_DIR}/anykernel_staging"
    rm -rf "${STAGING_DIR}"
    mkdir -p "${STAGING_DIR}"

    cp -r "${ANYKERNEL_DIR}"/* "${STAGING_DIR}"/
    cp "${OUT_DIR}/arch/${ARCH}/boot/${KERNEL_IMAGE}" "${STAGING_DIR}/"
    
    # If standard Image.gz-dtb isn't enough, copy dtb separately if it exists
    if ls "${OUT_DIR}/arch/${ARCH}/boot/dts/qcom/"*.dtb 1> /dev/null 2>&1; then
        mkdir -p "${STAGING_DIR}/dtbs"
        cp "${OUT_DIR}/arch/${ARCH}/boot/dts/qcom/"*.dtb "${STAGING_DIR}/dtbs/"
        log_info "Copied standalone DTBs to AnyKernel3 staging"
    fi
    
    log_info "Copied ${KERNEL_IMAGE} to AnyKernel3 staging"

    local CFG_LOCALVER=""
    if [ -f "${OUT_DIR}/.config" ]; then
        CFG_LOCALVER=$(grep -Po '^CONFIG_LOCALVERSION="\K[^"]*' "${OUT_DIR}/.config" || true)
        CFG_LOCALVER="${CFG_LOCALVER#-}" # Remove leading hyphen
    fi
    
    # Fallback jika kosong
    if [ -z "${CFG_LOCALVER}" ]; then
        CFG_LOCALVER="Kernel"
    fi

    local ZIP_NAME="${CFG_LOCALVER}-$(date +%Y%m%d-%H%M)"
    
    if test -z "$(git rev-parse --show-cdup 2>/dev/null)" && head=$(git rev-parse --verify HEAD 2>/dev/null); then
        ZIP_NAME="${ZIP_NAME}-$(echo $head | cut -c1-8)"
    fi
    ZIP_NAME="${ZIP_NAME}.zip"

    mkdir -p "${ZIP_DIR}"

    cd "${STAGING_DIR}"
    zip -r9 "${ZIP_DIR}/${ZIP_NAME}" . \
        -x '*.git*' \
        -x '*README*' \
        -x '*LICENSE*' \
        -x '*.md' \
        -x '*placeholders*'
    cd "${KERNEL_DIR}"

    rm -rf "${STAGING_DIR}"

    if [ ! -f "${ZIP_DIR}/${ZIP_NAME}" ]; then
        log_error "Failed to create flashable zip"
        exit 1
    fi

    local ZIP_SIZE
    ZIP_SIZE=$(du -h "${ZIP_DIR}/${ZIP_NAME}" | awk '{print $1}')

    log_success "Flashable zip created!"
    log_info "File: ${ZIP_DIR}/${ZIP_NAME}"
    log_info "Size: ${ZIP_SIZE}"

    echo -e "\n${GREEN}${BOLD}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                  BUILD COMPLETE!                  ║${NC}"
    echo -e "${GREEN}${BOLD}╠═══════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Kernel : ${CFG_LOCALVER}$(printf '%*s' $((27 - ${#CFG_LOCALVER})) '')${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Device : tucana (Mi Note 10)              ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Zip    : ${ZIP_NAME}$(printf '%*s' $((27 - ${#ZIP_NAME} + 12)) '')${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Size   : ${ZIP_SIZE}$(printf '%*s' $((34 - ${#ZIP_SIZE})) '')${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}╠═══════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Flash via TWRP/custom recovery:               ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  ${CYAN}adb sideload ${ZIP_NAME}${NC}$(printf '%*s' $((1)) '')${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Usage / Help
# ─────────────────────────────────────────────────────────────────────────────
show_help() {
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║     Cr-Tucana Kernel Build Script - sm6150        ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  Usage: $0 [OPTION]"
    echo ""
    echo "  Options:"
    echo "    (no args)    Full build: clean → defconfig → build → zip"
    echo "    --dirty      Build without cleaning (incremental build)"
    echo "    --clean      Only clean the build directory"
    echo "    --defconfig  Only generate the defconfig"
    echo "    --build      Only build the kernel (assumes defconfig exists)"
    echo "    --zip        Only package the zip (assumes kernel is built)"
    echo "    --help       Show this help message"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  Main entry point
# ─────────────────────────────────────────────────────────────────────────────
main() {
    local ACTION="full"

    for arg in "$@"; do
        case "${arg}" in
            --help|-h|--clean|--defconfig|--build|--zip|--dirty)
                ACTION="${arg}"
                ;;
            *)
                log_error "Unknown option: ${arg}"
                show_help
                exit 1
                ;;
        esac
    done

    if [ "${ACTION}" = "--help" ] || [ "${ACTION}" = "-h" ]; then
        show_help
        exit 0
    fi

    case "${ACTION}" in
        --clean)
            clean_build
            ;;
        --defconfig)
            preflight_check
            generate_defconfig
            ;;
        --build)
            preflight_check
            build_kernel
            ;;
        --zip)
            preflight_check
            package_zip
            ;;
        --dirty)
            preflight_check
            generate_defconfig
            build_kernel
            package_zip
            ;;
        full)
            preflight_check
            clean_build
            generate_defconfig
            build_kernel
            package_zip
            ;;
    esac
}

# Run
main "$@"
