# LEANN HTTP Server Docker Image
# Optimized for serving law indexes with DiskANN backend
# Handles MKL library dependencies

FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install Python, pip, git, curl and system dependencies for DiskANN backend + Intel MKL
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    git \
    curl \
    build-essential \
    cmake \
    libboost-all-dev \
    libprotobuf-dev \
    protobuf-compiler \
    libzmq3-dev \
    libabsl-dev \
    libomp-dev \
    libmkl-full-dev \
    libaio-dev \
    && rm -rf /var/lib/apt/lists/*

# Install uv for faster package installation
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Set working directory
WORKDIR /app

# Copy entire repository (including .git for submodules)
COPY . /app/

# Initialize git submodules for backend dependencies
RUN git submodule update --init --recursive

# Install Python dependencies and LEANN packages using uv (much faster than pip)
# Using --system and --break-system-packages flags (safe in isolated Docker container)
RUN uv pip install --system --break-system-packages \
    /app/packages/leann-core \
    /app/packages/leann-backend-hnsw \
    /app/packages/leann-backend-diskann

# Install HTTP server dependencies (not included in base package)
RUN uv pip install --system --break-system-packages \
    uvicorn \
    fastapi \
    websockets \
    sse-starlette \
    python-multipart

# Fix MKL symlinks for DiskANN backend
# This addresses the MKL library loading issue described in MKL_TROUBLESHOOTING.md
RUN DISKANN_LIBS=$(python3 -c "import leann_backend_diskann; import os; print(os.path.join(os.path.dirname(leann_backend_diskann.__file__), '.libs'))" 2>/dev/null || echo "") && \
    if [ -d "$DISKANN_LIBS" ]; then \
    cd "$DISKANN_LIBS" && \
    for lib in /usr/lib/x86_64-linux-gnu/libmkl*.so*; do \
    if [ -f "$lib" ]; then \
    basename_lib=$(basename $lib .so); \
    ln -sf $lib ${basename_lib}.so.2 2>/dev/null || true; \
    fi; \
    done; \
    fi

# Create directory for mounted indexes
RUN mkdir -p /indexes

# Expose default port (will be overridden per container)
EXPOSE 8000

# Set default environment variables
ENV PYTHONUNBUFFERED=1

# Copy and set up entrypoint script
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]

# Default command arguments (overridden by compose file)
CMD ["--index-path", "/indexes", "--port", "8000", "--llm-type", "openai", "--model", "gpt-oss-120b"]
