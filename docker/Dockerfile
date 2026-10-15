# v2: everything in one container. Supervisor = supervisord.
FROM debian:trixie-slim
ARG NODE_VER=24.21.0
ENV TZ=Asia/Shanghai LANG=C.UTF-8
RUN sed -i 's#http://deb.debian.org#http://mirrors.tencentyun.com#g' /etc/apt/sources.list.d/debian.sources \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openjdk-25-jre-headless openssh-server supervisor cron tzdata python3 curl xz-utils \
      tini util-linux procps ca-certificates less nano tar gzip \
 && curl -fsSL "https://mirrors.tencent.com/nodejs-release/v${NODE_VER}/node-v${NODE_VER}-linux-x64.tar.xz" \
      | tar -xJ -C /usr/local --strip-components=1 \
 && apt-get purge -y xz-utils && rm -rf /var/lib/apt/lists/* \
 && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo Asia/Shanghai > /etc/timezone \
 && groupadd -g 989 minecraft && useradd -u 999 -g 989 -d /srv/minecraft -s /usr/sbin/nologin -M minecraft \
 && groupadd -g 1001 ytang && useradd -u 1001 -g 1001 -d /home/ytang -s /usr/sbin/nologin -m ytang \
 && mkdir -p /run/sshd /root/.ssh /var/log/minecraft /etc/rclone /usr/local/share/minecraft-admin \
 && chmod 700 /root/.ssh && rm -f /etc/ssh/ssh_host_*
# host-sourced tools, copied into ./host by migrate-v2.sh (no secrets)
COPY host/rclone /usr/bin/rclone
COPY host/minecraft-afk-azalea /usr/local/bin/minecraft-afk-azalea
COPY host/minecraft-admin host/minecraft-rcon host/minecraft-backup-upload host/minecraft-notify-failure /usr/local/sbin/
COPY host/templates/ /usr/local/share/minecraft-admin/
COPY rootfs/ /
COPY sshd_config /etc/ssh/sshd_config
COPY authorized_keys /root/.ssh/authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys \
 && chmod 755 /usr/local/bin/* /usr/local/sbin/* /usr/bin/rclone /usr/bin/systemctl /usr/bin/journalctl \
 && chmod 644 /etc/cron.d/minecraft \
 && ln -sf /etc/minecraft-secrets/rclone.conf /etc/rclone/rclone.conf \
 && ln -sf /etc/minecraft-secrets/minecraft-notify.env /etc/minecraft-notify.env
WORKDIR /srv/minecraft
EXPOSE 25565 22
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
