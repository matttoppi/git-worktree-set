# Image for the removal safety comparison. Build from the repository root:
#   docker build -f comparison/removal-safety/Dockerfile -t worktree-removal-safety .
#   docker run --rm worktree-removal-safety
FROM golang:bookworm
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 python3-venv python3-pip pipx nodejs npm jq tmux expect \
  && rm -rf /var/lib/apt/lists/*
ENV PATH=/root/go/bin:/root/.local/bin:$PATH
# The install scripts come first, so that a change to an adapter or to the
# harness does not install the tools again.
COPY comparison/removal-safety/install /comparison/install
# Each tool has one install script. A failed install stops the build.
# --build-arg TOOLS="a b" installs only those tools.
ARG TOOLS=
RUN if [ -n "$TOOLS" ]; then scripts=$(for tool in $TOOLS; do echo "/comparison/install/$tool.sh"; done); \
    else scripts=$(ls /comparison/install/*.sh); fi; \
    for script in $scripts; do [ -f "$script" ] || continue; echo "== $script"; bash "$script" || exit 1; done
COPY git-worktree-set /usr/local/bin/git-worktree-set
COPY comparison/removal-safety /comparison
WORKDIR /comparison
CMD ["bash", "run_comparison.sh"]
