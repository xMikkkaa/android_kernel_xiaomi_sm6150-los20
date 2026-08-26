#!/usr/bin/env bash
# ============================================================================
#  Tucana Kernel Build Script for Xiaomi Mi Note 10 / CC9 Pro (tucana)
#  Kernel: Linux 4.14.180 (arm64 / SM6150 / sdmmagpie)
#  Toolchain: AOSP Clang 10.0.6 (clang-r370808) + GCC 4.9
#  Author: xMikkkaa
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

# AOSP Clang 10.0.6 (clang-r370808) toolchain
CLANG_DIR="${HOME}/xMik-Project/toolchains/clang-r370808"
CLANG_BIN="${CLANG_DIR}/bin"

# GCC cross-compiler toolchains (required as assembler/linker backend)
GCC64_DIR="${HOME}/xMik-Project/toolchains/gcc-arm64"
GCC64_BIN="${GCC64_DIR}/bin"
GCC32_DIR="${HOME}/xMik-Project/toolchains/gcc-arm32"
GCC32_BIN="${GCC32_DIR}/bin"

# AnyKernel3 directory (for flashable zip packaging)
ANYKERNEL_DIR="${KERNEL_DIR}/tools/AnyKernel3"

# Output directory (out-of-tree build to keep source clean)
OUT_DIR="${KERNEL_DIR}/out"

# ─────────────────────────────────────────────────────────────────────────────
#  Build configurations
# ─────────────────────────────────────────────────────────────────────────────
# Defconfig (vendor subdirectory, QCOM style)
DEFCONFIG="vendor/tucana_user_defconfig"

# Architecture
ARCH="arm64"

# Target kernel image (Image.gz-dtb as configured in defconfig)
KERNEL_IMAGE="Image.gz-dtb"

# Number of parallel jobs (all available cores)
JOBS="$(nproc --all)"

# Kernel name for zip packaging
KERNEL_NAME="Tucana-Kernel"

# Zip output directory
ZIP_DIR="${KERNEL_DIR}/out/zip"

# ─────────────────────────────────────────────────────────────────────────────
#  Toolchain environment setup
#
#  This kernel (4.14) uses Clang as the compiler frontend but still relies
#  on GCC for the assembler (-no-integrated-as) and GNU binutils for
#  linking. This is NOT the same as modern LLVM=1 builds.
# ─────────────────────────────────────────────────────────────────────────────
export PATH="${CLANG_BIN}:${GCC64_BIN}:${GCC32_BIN}:${PATH}"
export ARCH="${ARCH}"
export SUBARCH="${ARCH}"
export KBUILD_BUILD_USER="xMikkkaa"

# ─────────────────────────────────────────────────────────────────────────────
#  Make arguments
#
#  Key differences from modern LLVM builds (like Chimera-V4):
#    - NO LLVM=1 or LLVM_IAS=1 (kernel too old)
#    - LD/AR/NM/STRIP/OBJCOPY/OBJDUMP all come from GCC, not LLVM
#    - Clang uses --target and --gcc-toolchain flags via Makefile auto-detect
#    - The Makefile adds -no-integrated-as automatically for clang
# ─────────────────────────────────────────────────────────────────────────────
MAKE_ARGS=(
    O="${OUT_DIR}"
    ARCH="${ARCH}"
    SUBARCH="${ARCH}"
    CC="clang"
    CLANG_TRIPLE="aarch64-linux-gnu-"
    CROSS_COMPILE="aarch64-linux-android-"
    CROSS_COMPILE_ARM32="arm-linux-androideabi-"
    LOCALVERSION=""
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

    # Check Clang
    if [ ! -x "${CLANG_BIN}/clang" ]; then
        log_error "Clang not found at ${CLANG_BIN}/clang"
        log_info "Download it with:"
        log_info "  git clone --depth=1 https://github.com/nicklela/prebuilt-clang-r370808.git ${CLANG_DIR}"
        exit 1
    fi

    local CLANG_VERSION
    CLANG_VERSION=$("${CLANG_BIN}/clang" --version | head -1)
    log_info "Clang: ${CLANG_VERSION}"

    # Check GCC aarch64 (we only need binutils: as, ld, ar, nm, etc.)
    if [ ! -x "${GCC64_BIN}/aarch64-linux-android-as" ]; then
        log_error "GCC aarch64 binutils not found at ${GCC64_BIN}/"
        log_info "Download it with:"
        log_info "  git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 -b android-11.0.0_r3 ${GCC64_DIR}"
        exit 1
    fi
    log_info "GCC64: binutils found at ${GCC64_BIN}/"

    # Check GCC arm32 (we only need binutils: as, ld, etc.)
    if [ ! -x "${GCC32_BIN}/arm-linux-androideabi-as" ]; then
        log_error "GCC arm32 binutils not found at ${GCC32_BIN}/"
        log_info "Download it with:"
        log_info "  git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 -b android-11.0.0_r3 ${GCC32_DIR}"
        exit 1
    fi
    log_info "GCC32: binutils found at ${GCC32_BIN}/"

    # Check Linker (GNU ld from GCC toolchain)
    if [ ! -x "${GCC64_BIN}/aarch64-linux-android-ld" ]; then
        log_error "GNU ld not found at ${GCC64_BIN}/aarch64-linux-android-ld"
        exit 1
    fi
    log_info "Linker: GNU ld (from GCC aarch64-linux-android-4.9)"

    # Check defconfig
    if [ ! -f "${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG}" ]; then
        log_error "Defconfig not found: arch/${ARCH}/configs/${DEFCONFIG}"
        exit 1
    fi
    log_info "Defconfig: ${DEFCONFIG}"

    # Check AnyKernel3
    if [ ! -d "${ANYKERNEL_DIR}" ]; then
        log_error "AnyKernel3 not found at ${ANYKERNEL_DIR}"
        exit 1
    fi
    if [ ! -f "${ANYKERNEL_DIR}/anykernel.sh" ]; then
        log_error "anykernel.sh not found in AnyKernel3 directory"
        exit 1
    fi
    log_info "AnyKernel3: ${ANYKERNEL_DIR}"

    log_info "Kernel: Linux 4.14.180"
    log_info "Device: Xiaomi Mi Note 10 / CC9 Pro (tucana / SM6150)"
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
    log_step "Generating Defconfig: ${DEFCONFIG}"

    make -C "${KERNEL_DIR}" "${MAKE_ARGS[@]}" "${DEFCONFIG}" -j"${JOBS}"

    if [ ! -f "${OUT_DIR}/.config" ]; then
        log_error "Failed to generate .config from ${DEFCONFIG}"
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
    log_info "Copied ${KERNEL_IMAGE} to AnyKernel3 staging"

    # Extract standalone dtb for AnyKernel3 (Pure Tucana only)
    if ls "${OUT_DIR}/arch/${ARCH}/boot/dts/qcom/"*tucana*.dtb 1> /dev/null 2>&1; then
        mkdir -p "${STAGING_DIR}/dtbs"
        cp "${OUT_DIR}/arch/${ARCH}/boot/dts/qcom/"*tucana*.dtb "${STAGING_DIR}/dtbs/"
        log_info "Copied standalone tucana DTBs to AnyKernel3 staging"
    fi

    local DATE_STR
    DATE_STR=$(date +"%Y%m%d-%H%M")
    local ZIP_NAME="${KERNEL_NAME}-${DATE_STR}.zip"

    mkdir -p "${ZIP_DIR}"
    rm -f "${ZIP_DIR}"/*.zip

    cd "${STAGING_DIR}"
    zip -r9 "${ZIP_DIR}/${ZIP_NAME}" . \
        -x '*.git*' \
        -x '*README*' \
        -x '*LICENSE*' \
        -x '*.md'
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
    echo -e "${GREEN}${BOLD}║${NC}  Kernel : ${KERNEL_NAME}$(printf '%*s' $((27 - ${#KERNEL_NAME})) '')${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Device : tucana (Mi Note 10 / CC9 Pro)       ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Zip    : ${ZIP_NAME}$(printf '%*s' $((27 - ${#ZIP_NAME} + 12)) '')${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Size   : ${ZIP_SIZE}$(printf '%*s' $((34 - ${#ZIP_SIZE})) '')${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}╠═══════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Flash via TWRP/custom recovery:               ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  ${CYAN}adb sideload ${ZIP_NAME}${NC}$(printf '%*s' $((1)) '')${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Step 5: Regenerate defconfig (optional, for development)
# ─────────────────────────────────────────────────────────────────────────────
regen_defconfig() {
    log_step "Regenerating Defconfig"

    make -C "${KERNEL_DIR}" "${MAKE_ARGS[@]}" savedefconfig -j"${JOBS}"

    if [ -f "${OUT_DIR}/defconfig" ]; then
        cp "${OUT_DIR}/defconfig" "${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG}"
        log_success "Defconfig regenerated and saved to arch/${ARCH}/configs/${DEFCONFIG}"
    else
        log_error "Failed to regenerate defconfig"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Usage / Help
# ─────────────────────────────────────────────────────────────────────────────
show_help() {
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║     Tucana Kernel Build Script - Mi Note 10       ║"
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
    echo "    --regen      Regenerate and save defconfig"
    echo "    --help       Show this help message"
    echo ""
    echo "  Toolchain:"
    echo "    Clang:  AOSP clang-r370808 (Clang 10.0.6)"
    echo "    GCC64:  aarch64-linux-android-4.9"
    echo "    GCC32:  arm-linux-androideabi-4.9"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  Main entry point
# ─────────────────────────────────────────────────────────────────────────────
main() {
    local ACTION="full"

    for arg in "$@"; do
        case "${arg}" in
            --help|-h|--clean|--defconfig|--build|--zip|--dirty|--regen)
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
        --regen)
            preflight_check
            regen_defconfig
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
