#!/bin/bash

# QuickJS-KT Local Maven Publisher
# Supports macOS and Linux platforms for local development and CI/CD environments
#
# Usage:
#   ./publish-local.sh              # Normal mode with detailed output
#   ./publish-local.sh --quiet      # Quiet mode for CI (minimal output)
#   ./publish-local.sh --ci         # Alias for --quiet
#   ./publish-local.sh --help       # Show help

set -e  # Exit on error

# Parse arguments
QUIET_MODE=false
SKIP_CLEAN=false

for arg in "$@"; do
    case $arg in
        --quiet|--ci|-q)
            QUIET_MODE=true
            shift
            ;;
        --skip-clean)
            SKIP_CLEAN=true
            shift
            ;;
        --help|-h)
            echo "QuickJS-KT Local Maven Publisher"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --quiet, --ci, -q    Quiet mode for CI (minimal output)"
            echo "  --skip-clean         Skip the clean step"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                   # Normal mode"
            echo "  $0 --quiet           # CI mode"
            echo "  $0 --skip-clean      # Skip clean, faster rebuild"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Color codes for output
if [ "$QUIET_MODE" = true ]; then
    # No colors in quiet mode
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
fi

# Logging functions
log_info() {
    if [ "$QUIET_MODE" = true ]; then
        echo "ℹ️  $1"
    else
        echo -e "${GREEN}$1${NC}"
    fi
}

log_error() {
    if [ "$QUIET_MODE" = true ]; then
        echo "❌ $1" >&2
    else
        echo -e "${RED}$1${NC}" >&2
    fi
}

log_warn() {
    if [ "$QUIET_MODE" = true ]; then
        echo "⚠️  $1"
    else
        echo -e "${YELLOW}$1${NC}"
    fi
}

log_section() {
    if [ "$QUIET_MODE" = false ]; then
        echo ""
        echo "================================================"
        echo "$1"
        echo "================================================"
    fi
}

log_step() {
    if [ "$QUIET_MODE" = true ]; then
        echo "▶️  $1"
    else
        echo ""
        echo "$1"
    fi
}

# Header
if [ "$QUIET_MODE" = false ]; then
    log_section "QuickJS-KT Local Maven Publisher"
fi

# Detect OS and Architecture
OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH_TYPE=$(uname -m)

log_info "Detected OS: ${OS_TYPE}"
log_info "Detected Architecture: ${ARCH_TYPE}"

# Normalize architecture names
case "${ARCH_TYPE}" in
    x86_64|amd64)
        ARCH="x64"
        ;;
    aarch64|arm64)
        ARCH="aarch64"
        ;;
    *)
        log_error "Unsupported architecture: ${ARCH_TYPE}"
        exit 1
        ;;
esac

# Normalize OS names
case "${OS_TYPE}" in
    darwin)
        OS="macos"
        # For macOS, use arm64 instead of aarch64
        if [ "${ARCH}" = "aarch64" ]; then
            ARCH="aarch64"
            ARCH_DISPLAY="arm64"
        else
            ARCH_DISPLAY="x64"
        fi
        ;;
    linux)
        OS="linux"
        ARCH_DISPLAY="${ARCH}"
        ;;
    *)
        log_error "Unsupported operating system: ${OS_TYPE}"
        exit 1
        ;;
esac

log_info "Platform: ${OS}_${ARCH_DISPLAY}"

# Detect JAVA_HOME
if [ -z "${JAVA_HOME}" ]; then
    log_warn "JAVA_HOME not set, attempting to detect..."
    
    if [ "${OS}" = "macos" ]; then
        # macOS: use java_home utility
        if command -v /usr/libexec/java_home &> /dev/null; then
            JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null || echo "")
        fi
    elif [ "${OS}" = "linux" ]; then
        # Linux: try common locations
        if command -v java &> /dev/null; then
            JAVA_BIN=$(which java)
            JAVA_HOME=$(readlink -f "${JAVA_BIN}" | sed "s:/bin/java::")
        fi
    fi
    
    if [ -z "${JAVA_HOME}" ]; then
        log_error "ERROR: JAVA_HOME could not be detected automatically."
        log_error "Please set JAVA_HOME environment variable and try again."
        exit 1
    fi
fi

log_info "Using JAVA_HOME: ${JAVA_HOME}"

# Create/update local.properties with platform-specific JAVA_HOME
LOCAL_PROPS="local.properties"
log_step "Configuring ${LOCAL_PROPS}..."

# Backup existing local.properties if it exists
if [ -f "${LOCAL_PROPS}" ] && [ "$QUIET_MODE" = false ]; then
    cp "${LOCAL_PROPS}" "${LOCAL_PROPS}.backup"
    log_info "Backed up existing ${LOCAL_PROPS} to ${LOCAL_PROPS}.backup"
fi

# Determine the JAVA_HOME key for this platform
OS_UPPER=$(echo "${OS}" | tr '[:lower:]' '[:upper:]')
ARCH_UPPER=$(echo "${ARCH}" | tr '[:lower:]' '[:upper:]')
JAVA_HOME_KEY="JAVA_HOME_${OS_UPPER}_${ARCH_UPPER}"
if [ "${OS}" = "macos" ] && [ "${ARCH}" = "aarch64" ]; then
    JAVA_HOME_KEY="JAVA_HOME_MACOS_AARCH64"
fi

log_info "Setting ${JAVA_HOME_KEY}=${JAVA_HOME}"

# Update or add the JAVA_HOME entry
if [ -f "${LOCAL_PROPS}" ]; then
    # Check if the key already exists
    if grep -q "^${JAVA_HOME_KEY}=" "${LOCAL_PROPS}"; then
        # Update existing entry
        sed -i.tmp "s|^${JAVA_HOME_KEY}=.*|${JAVA_HOME_KEY}=${JAVA_HOME}|" "${LOCAL_PROPS}"
        rm -f "${LOCAL_PROPS}.tmp"
    else
        # Add new entry
        echo "${JAVA_HOME_KEY}=${JAVA_HOME}" >> "${LOCAL_PROPS}"
    fi
else
    # Create new file with sdk.dir placeholder
    echo "# Auto-generated by publish-local.sh" > "${LOCAL_PROPS}"
    if [ "${OS}" = "macos" ]; then
        echo "sdk.dir=\${HOME}/Library/Android/sdk" >> "${LOCAL_PROPS}"
    else
        echo "sdk.dir=\${HOME}/Android/Sdk" >> "${LOCAL_PROPS}"
    fi
    echo "${JAVA_HOME_KEY}=${JAVA_HOME}" >> "${LOCAL_PROPS}"
fi

log_step "Setting executable permissions on scripts..."

# Make gradlew executable
if [ -f "gradlew" ]; then
    chmod +x gradlew
    [ "$QUIET_MODE" = false ] && echo "✓ gradlew"
fi

# Make cmake scripts executable
if [ -d "quickjs/native/cmake" ]; then
    chmod +x quickjs/native/cmake/*.sh 2>/dev/null || true
    [ "$QUIET_MODE" = false ] && echo "✓ quickjs/native/cmake/*.sh"
fi

log_section "Starting build and publish process..."

# Gradle arguments
GRADLE_ARGS=""
if [ "$QUIET_MODE" = true ]; then
    GRADLE_ARGS="-q"
fi

# Clean build (optional)
if [ "$SKIP_CLEAN" = false ]; then
    log_step "Step 1/3: Cleaning previous build..."
    ./gradlew clean $GRADLE_ARGS
else
    log_info "Skipping clean step"
fi

# Build
log_step "Step 2/3: Building project..."
./gradlew build $GRADLE_ARGS

# Publish to Maven Local
log_step "Step 3/3: Publishing to Maven Local..."
./gradlew publishToMavenLocal $GRADLE_ARGS

# Success message
if [ "$QUIET_MODE" = false ]; then
    log_section "✓ Successfully published to Maven Local!"
    echo ""
    echo "Published modules:"
    echo "  - com.dokar.quickjs:quickjs"
    echo "  - com.dokar.quickjs:quickjs-converter-ktxserialization"
    echo "  - com.dokar.quickjs:quickjs-converter-moshi"
    echo ""
    echo "Maven Local Repository:"
    echo "  ~/.m2/repository"
    echo ""
    echo "To use in your project, add to build.gradle.kts:"
    echo ""
    echo "  repositories {"
    echo "      mavenLocal()"
    echo "      // ... other repositories"
    echo "  }"
    echo ""
else
    echo "✅ Successfully published to ~/.m2/repository"
fi

