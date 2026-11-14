# Debian with cron and no systemd, so the scheduler picks the cron backend. No jq either, so the runner's
# sed fallbacks for Claude's output are the ones in use.
FROM debian:12-slim
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends cron procps \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -u 1001 -s /bin/bash runner
COPY claude-stub.sh /usr/local/bin/claude
CMD ["cron", "-f"]
