# Flash CLI Framework - Test Environment
# Alpine-based container with Zig (mounted from host) and Valgrind

FROM alpine:3.19

# Install build dependencies and Valgrind
RUN apk add --no-cache \
    bash \
    coreutils \
    valgrind \
    git \
    curl \
    musl-dev \
    && rm -rf /var/cache/apk/*

# Create non-root user for builds
RUN adduser -D -h /home/flash flash

# Working directory
WORKDIR /workspace

# Zig will be mounted from host at /opt/zig
# Project will be mounted at /workspace

# Add zig to PATH
ENV PATH="/opt/zig:${PATH}"

# Switch to non-root user
USER flash

# Default command
CMD ["/bin/bash"]
