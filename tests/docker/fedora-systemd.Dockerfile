# Fedora with systemd as PID 1: the systemd path again on other builds of systemctl and coreutils.
FROM fedora:41
RUN dnf install -y --setopt=install_weak_deps=False systemd dbus-daemon jq procps-ng shadow-utils util-linux \
 && dnf clean all \
 && useradd -m -u 1001 -s /bin/bash runner \
 && mkdir -p /var/lib/systemd/linger && touch /var/lib/systemd/linger/runner
COPY claude-stub.sh /usr/local/bin/claude
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
