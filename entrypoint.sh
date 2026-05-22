#!/bin/bash
set -e

# ──────────────────────────────────────────────────────────────
# Samba AD DC Docker Entrypoint
# Provisions a new domain or starts from existing configuration.
# ──────────────────────────────────────────────────────────────

REALM="${REALM:-LAB.INTERNAL}"
DOMAIN="${DOMAIN:-LAB}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-Admin.1.samba}"
DNS_FORWARDER="${DNS_FORWARDER:-8.8.8.8}"
HOSTNAME="${SAMBA_HOSTNAME:-$(hostname)}"

REALM_LOWER=$(echo "$REALM" | tr '[:upper:]' '[:lower:]')
IFS='.' read -ra REALM_PARTS <<< "$REALM_LOWER"
BASE_DN=$(printf ",DC=%s" "${REALM_PARTS[@]}")
BASE_DN="${BASE_DN:1}" # Remove leading comma

echo "============================================="
echo "  Samba AD DC Container"
echo "============================================="
echo "  Realm:          $REALM"
echo "  Domain:         $DOMAIN"
echo "  Hostname:       $HOSTNAME"
echo "  DNS Forwarder:  $DNS_FORWARDER"
echo "  Base DN:        $BASE_DN"
echo "============================================="

# ──────────────────────────────────────────────────────────────
# Configure /etc/hosts
# ──────────────────────────────────────────────────────────────
configure_hosts() {
    echo ">>> Configuring /etc/hosts..."
    CONTAINER_IP=$(hostname -I | awk '{print $1}')

    cat > /etc/hosts <<EOF
127.0.0.1       localhost
${CONTAINER_IP}  ${HOSTNAME}.${REALM_LOWER} ${HOSTNAME}

::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
    echo ">>> /etc/hosts configured with IP: $CONTAINER_IP"
}

# ──────────────────────────────────────────────────────────────
# Configure DNS resolver to use Samba's internal DNS
# ──────────────────────────────────────────────────────────────
configure_dns() {
    echo ">>> Configuring DNS resolver..."
    cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
search ${REALM_LOWER}
EOF
    echo ">>> DNS resolver configured."
}

# ──────────────────────────────────────────────────────────────
# Provision a brand-new Samba AD domain
# ──────────────────────────────────────────────────────────────
provision_domain() {
    echo ">>> Provisioning new Samba AD domain..."

    # Stop any running samba services
    if pgrep -x samba > /dev/null 2>&1; then
        kill "$(pgrep -x samba)" 2>/dev/null || true
        sleep 2
    fi

    # Remove any stale config
    rm -f /etc/samba/smb.conf

    # Provision the domain
    samba-tool domain provision \
        --use-rfc2307 \
        --realm="$REALM" \
        --domain="$DOMAIN" \
        --server-role=dc \
        --dns-backend=SAMBA_INTERNAL \
        --adminpass="$ADMIN_PASSWORD" \
        --option="dns forwarder = $DNS_FORWARDER" \
        --option="bind interfaces only = no" \
        --option="ldap server require strong auth = no"

    echo ">>> Domain provisioned successfully."

    # Configure Kerberos
    echo ">>> Configuring Kerberos..."
    cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

    # Enhance krb5.conf with explicit KDC entries if missing
    if ! grep -q "kdc" /etc/krb5.conf; then
        cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = ${REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    ${REALM} = {
        kdc = ${HOSTNAME}.${REALM_LOWER}
        admin_server = ${HOSTNAME}.${REALM_LOWER}
        default_domain = ${REALM_LOWER}
    }

[domain_realm]
    .${REALM_LOWER} = ${REALM}
    ${REALM_LOWER} = ${REALM}
EOF
    fi

    echo ">>> Kerberos configured."

    # Mark as provisioned
    touch /var/lib/samba/.provisioned
}

# ──────────────────────────────────────────────────────────────
# Start Samba AD DC in the foreground
# ──────────────────────────────────────────────────────────────
start_samba() {
    echo ">>> Starting Samba AD DC..."
    exec samba --foreground --no-process-group
}

# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────

configure_hosts

# Check if already provisioned
if [ -f /var/lib/samba/.provisioned ] && [ -f /etc/samba/smb.conf ]; then
    echo ">>> Existing domain detected. Reusing configuration."
else
    provision_domain
fi

# Ensure plaintext LDAP simple binds are allowed (for dev/test convenience)
if ! grep -q "ldap server require strong auth" /etc/samba/smb.conf; then
    sed -i '/\[global\]/a \\tldap server require strong auth = no' /etc/samba/smb.conf
    echo ">>> Enabled plaintext LDAP simple binds."
fi

configure_dns

# Setup test users in the background (after samba starts)
if [ "${CREATE_TEST_USERS:-true}" = "true" ]; then
    (
        sleep 10
        /usr/local/bin/setup-users.sh
    ) &
fi

start_samba
