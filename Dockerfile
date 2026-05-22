FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Non-sensitive defaults only — secrets come from .env / environment
ENV REALM=LAB.INTERNAL
ENV DOMAIN=LAB
ENV DNS_FORWARDER=8.8.8.8

# Install Samba AD DC and required tools
RUN apt-get update && apt-get install -y \
    samba \
    krb5-user \
    winbind \
    smbclient \
    ldap-utils \
    dnsutils \
    libsasl2-modules-gssapi-mit \
    netcat-openbsd \
    procps \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# Copy entrypoint and helper scripts
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY setup-users.sh /usr/local/bin/setup-users.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    /usr/local/bin/setup-users.sh \
    /usr/local/bin/healthcheck.sh

# Expose required ports
# 53   - DNS (tcp/udp)
# 88   - Kerberos (tcp/udp)
# 135  - RPC Endpoint Mapper
# 137  - NetBIOS Name Service (udp)
# 138  - NetBIOS Datagram (udp)
# 139  - NetBIOS Session
# 389  - LDAP (tcp/udp)
# 445  - SMB
# 464  - Kerberos kpasswd (tcp/udp)
# 636  - LDAPS
# 3268 - Global Catalog
# 3269 - Global Catalog SSL
EXPOSE 53 53/udp 88 88/udp 135 137/udp 138/udp 139 389 389/udp 445 464 464/udp 636 3268 3269

# Persistent data volume
VOLUME ["/var/lib/samba", "/etc/samba"]

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
