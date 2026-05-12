FROM node:22-bookworm-slim

# Tools the harness needs:
#   tmux       — backgrounding the channel server (matches BACKGROUNDING.md)
#   expect     — fallback for AskUserQuestion if pty-drive.py isn't enough
#   util-linux — provides script(1) for the script(1) backgrounding fallback
#   curl/jq    — Bot API drive (sendMessage / getUpdates)
#   python3    — pty-drive.py
#   git        — claude code uses git for some operations
#   procps     — pgrep/ps for process detection in skills' Step 7a
RUN apt-get update && apt-get install -y --no-install-recommends \
      tmux \
      expect \
      bsdmainutils \
      util-linux \
      curl \
      jq \
      python3 \
      python3-pip \
      git \
      procps \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Pin claude code so harness runs are reproducible. Bump explicitly when
# upgrading; don't auto-pull latest.
ARG CLAUDE_CODE_VERSION=2.1.138
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# `claude` writes state under $HOME/.claude. We run as the pre-existing
# `node` user (UID 1000, comes with node:22-bookworm-slim) so the
# bind-mounted reports/ on the host doesn't end up root-owned. The
# container HOME doubles as the sandbox HOME — there's no isolation
# layer needed inside the container.
USER node
WORKDIR /home/node

# Repo gets bind-mounted at /repo by docker/run.sh. Drivers live there.
ENV REPO_ROOT=/repo
ENV HARNESS_ROOT=/repo/test-harness

# Default to a shell — the entrypoint is the driver path passed by run.sh.
CMD ["/bin/bash"]
