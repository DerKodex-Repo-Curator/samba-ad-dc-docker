#!/bin/bash
# ──────────────────────────────────────────────────────────────
# Setup test users and configure password/lockout policies.
# This script runs after Samba AD DC is fully started.
# ──────────────────────────────────────────────────────────────

REALM="${REALM:-LAB.INTERNAL}"
REALM_LOWER=$(echo "$REALM" | tr '[:upper:]' '[:lower:]')
ADMIN_PASSWORD="${ADMIN_PASSWORD:-Admin.1.samba}"
PASSWORD_SUFFIX="${TEST_USER_PASSWORD_SUFFIX:-.1.Samba}"

LOCKOUT_THRESHOLD="${LOCKOUT_THRESHOLD:-3}"
LOCKOUT_DURATION="${LOCKOUT_DURATION:-5}"
LOCKOUT_OBSERVATION_WINDOW="${LOCKOUT_OBSERVATION_WINDOW:-5}"

echo "============================================="
echo "  Setting up test users and policies"
echo "============================================="

# Wait for LDAP to be available
echo ">>> Waiting for Samba LDAP to become available..."
for i in $(seq 1 30); do
    if ldapsearch -x -H ldap://localhost -D "administrator@${REALM}" -w "$ADMIN_PASSWORD" -b "DC=${REALM_LOWER%%.*},DC=${REALM_LOWER#*.}" "(objectClass=domain)" dn > /dev/null 2>&1; then
        echo ">>> LDAP is ready."
        break
    fi
    echo ">>> Waiting... ($i/30)"
    sleep 2
done

# ──────────────────────────────────────────────────────────────
# Create test users
# ──────────────────────────────────────────────────────────────
echo ">>> Creating test users..."

create_user() {
    local username="$1"
    local given_name="$2"
    local surname="$3"
    local email="$4"
    local password="${username}${PASSWORD_SUFFIX}"

    if samba-tool user list 2>/dev/null | grep -q "^${username}$"; then
        echo "    User '${username}' already exists. Skipping."
    else
        samba-tool user create "$username" "$password" \
            --given-name="$given_name" \
            --surname="$surname" \
            --mail-address="$email" \
            --use-username-as-cn \
            2>/dev/null && echo "    Created user: $username (password: $password)" || echo "    Failed to create user: $username"
    fi
}

create_user "testuser"  "Test"   "User"     "testuser@${REALM_LOWER}"
create_user "jdoe"      "John"   "Doe"      "jdoe@${REALM_LOWER}"
create_user "jsmith"    "Jane"   "Smith"    "jsmith@${REALM_LOWER}"
create_user "locktest"  "Lock"   "Test"     "locktest@${REALM_LOWER}"

# ──────────────────────────────────────────────────────────────
# Create test group
# ──────────────────────────────────────────────────────────────
if ! samba-tool group list 2>/dev/null | grep -q "^TestUsers$"; then
    samba-tool group add TestUsers 2>/dev/null && echo "    Created group: TestUsers" || true
    samba-tool group addmembers TestUsers testuser,jdoe,jsmith,locktest 2>/dev/null || true
    echo "    Added users to TestUsers group."
else
    echo "    Group 'TestUsers' already exists. Skipping."
fi

# ──────────────────────────────────────────────────────────────
# Configure lockout policy
# ──────────────────────────────────────────────────────────────
echo ""
echo ">>> Configuring account lockout policy..."
samba-tool domain passwordsettings set \
    --account-lockout-threshold="$LOCKOUT_THRESHOLD" \
    --account-lockout-duration="$LOCKOUT_DURATION" \
    --reset-account-lockout-after="$LOCKOUT_OBSERVATION_WINDOW" \
    2>/dev/null

# Relax password complexity for testing convenience
samba-tool domain passwordsettings set \
    --complexity=off \
    --min-pwd-length=6 \
    --min-pwd-age=0 \
    --max-pwd-age=0 \
    2>/dev/null

echo ""
echo ">>> Current password/lockout policy:"
samba-tool domain passwordsettings show 2>/dev/null

echo ""
echo "============================================="
echo "  Setup complete!"
echo ""
echo "  Test Users (password = <username>${PASSWORD_SUFFIX})"
echo "    - testuser"
echo "    - jdoe"
echo "    - jsmith"
echo "    - locktest"
echo ""
echo "  Group: TestUsers"
echo ""
echo "  Lockout Policy:"
echo "    - Threshold: ${LOCKOUT_THRESHOLD} failed attempts"
echo "    - Duration:  ${LOCKOUT_DURATION} minutes"
echo "============================================="
