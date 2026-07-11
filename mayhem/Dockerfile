# syntax=docker/dockerfile:1.7
FROM ghcr.io/mayhemheroes/base:20260621

# Undefaulted (no =) so the base ENV default flows through unless --build-arg overrides it.
ARG SANITIZER_FLAGS

# ── Rust toolchain @ a FIXED, lockable, $HOME-independent prefix ───────────────
# Pin the channel by DATE for reproducibility.
ARG RUST_CHANNEL=nightly-2025-05-14
ARG CARGO_FUZZ_VERSION=0.12.0

ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:${PATH}

USER root
RUN install -d /opt/toolchains/rust \
 && curl --proto "=https" --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
 && sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_CHANNEL}" \
 && rustup component add rust-src --toolchain "${RUST_CHANNEL}" \
 && rustup toolchain install stable --profile minimal \
 && cargo install cargo-fuzz --version "${CARGO_FUZZ_VERSION}" --locked \
 && rm -f /tmp/rustup-init.sh \
 && chown -R 2000:2000 /opt/toolchains/rust

# Put build-specific ARGs AFTER the toolchain layer so changing COMMIT
# does not invalidate the cached Rust toolchain layer.
ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN bash -c "if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo no test.sh; fi"

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
