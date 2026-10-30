# Ubuntu LTS with systemd as PID 1, for section 26's live systemd run (AW_TEST_DOCKER=1). A user, runner,
# has lingering on, so its user manager starts at boot and its timers fire with nobody logged in.
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends systemd systemd-sysv dbus dbus-user-session jq procps \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -u 1001 -s /bin/bash runner \
 && mkdir -p /var/lib/systemd/linger && touch /var/lib/systemd/linger/runner
COPY claude-stub.sh /usr/local/bin/claude
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
