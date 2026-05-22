#!/bin/bash
# Healthcheck: verify LDAP TCP is listening and responding

REALM="${REALM:-LAB.INTERNAL}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-Password123!}"
REALM_LOWER=$(echo "$REALM" | tr '[:upper:]' '[:lower:]')

# Check TCP port 389 is listening
nc -z 127.0.0.1 389 || exit 1

# Check LDAP responds to a basic query
ldapsearch -x \
    -H ldap://localhost \
    -D "administrator@${REALM}" \
    -w "$ADMIN_PASSWORD" \
    -b "DC=${REALM_LOWER%%.*},DC=${REALM_LOWER#*.}" \
    -s base "(objectClass=domain)" dn > /dev/null 2>&1 || exit 1

exit 0
