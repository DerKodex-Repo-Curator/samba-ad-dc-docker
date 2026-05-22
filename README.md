# Samba AD DC — Docker

A self-contained Docker setup for running a **Samba Active Directory Domain Controller** on macOS, Linux, or any Docker-capable host. Useful for LDAP development, testing AD-integrated applications, and exploring Active Directory semantics without a Windows Server.

## Features

- **One-command setup** — `docker compose up -d` provisions a fully functional AD domain
- **LDAP on localhost** — no network configuration, firewall rules, or DNS hacks
- **Pre-created test users** — optional sample accounts with configurable passwords
- **Configurable lockout policy** — threshold, duration, and observation window via `.env`
- **Persistent data** — domain state survives container restarts via Docker volumes
- **Plaintext LDAP binds** — enabled by default for dev/test convenience (`ldap server require strong auth = no`)

---

## Quick Start

```bash
# 1. Copy the example config and adjust if needed
cp .env.example .env

# 2. Build and start the container
docker compose up -d --build

# 3. Follow logs until you see "Setup complete!"
docker compose logs -f
```

### Connection Details

| Setting          | Value                                                     |
|------------------|-----------------------------------------------------------|
| **LDAP Host**    | `localhost`                                               |
| **LDAP Port**    | `389`                                                     |
| **LDAPS Port**   | `636`                                                     |
| **Base DN**      | `DC=lab,DC=internal`                                      |
| **Admin Bind**   | `administrator@LAB.INTERNAL`                              |
| **Admin DN**     | `CN=Administrator,CN=Users,DC=lab,DC=internal`            |
| **Admin Password** | Value of `ADMIN_PASSWORD` in `.env` (default: `Admin.1.samba`) |
| **Kerberos Realm** | `LAB.INTERNAL`                                          |
| **Global Catalog** | `localhost:3268`                                        |

### Test Users

Created when `CREATE_TEST_USERS=true` (default). Password pattern: `<username>.1.Samba`

| Username   | Password                   | Email                   |
|------------|----------------------------|-------------------------|
| `testuser` | `testuser.1.Samba`         | testuser@lab.internal   |
| `jdoe`     | `jdoe.1.Samba`             | jdoe@lab.internal       |
| `jsmith`   | `jsmith.1.Samba`           | jsmith@lab.internal     |
| `locktest` | `locktest.1.Samba`         | locktest@lab.internal   |

All users are members of the `TestUsers` group.

---

## Configuration

All settings are managed via a `.env` file. See [`.env.example`](.env.example) for the full list.

| Variable                     | Default              | Description                              |
|------------------------------|----------------------|------------------------------------------|
| `REALM`                      | `LAB.INTERNAL`       | Kerberos realm (uppercase)               |
| `DOMAIN`                     | `LAB`                | NetBIOS domain name                      |
| `ADMIN_PASSWORD`             | `Admin.1.samba`    | Domain Administrator password          |
| `DNS_FORWARDER`              | `8.8.8.8`            | DNS forwarder for external queries       |
| `SAMBA_HOSTNAME`             | `dc1`                | Hostname for the DC                      |
| `CREATE_TEST_USERS`          | `true`               | Create sample users on first start       |
| `TEST_USER_PASSWORD_SUFFIX`  | `.1.Samba`         | Appended to username for test passwords  |
| `LOCKOUT_THRESHOLD`          | `3`                  | Failed attempts before lockout           |
| `LOCKOUT_DURATION`           | `5`                  | Lockout duration (minutes)               |
| `LOCKOUT_OBSERVATION_WINDOW` | `5`                  | Reset failed count after (minutes)       |

---

## Common LDAP Queries

> **Note:** Use single quotes around the password to avoid shell expansion of special characters.

### Query a user

```bash
ldapsearch -x \
  -H ldap://localhost \
  -D 'administrator@LAB.INTERNAL' \
  -w 'Admin.1.samba' \
  -b 'dc=lab,dc=internal' \
  '(sAMAccountName=testuser)'
```

### Query with operational attributes

```bash
ldapsearch -x \
  -H ldap://localhost \
  -D 'administrator@LAB.INTERNAL' \
  -w 'Admin.1.samba' \
  -b 'dc=lab,dc=internal' \
  '(sAMAccountName=testuser)' \
  '*' '+'
```

### Query domain lockout policy

`lockoutDuration` is a **domain-level** attribute (not per-user):

```bash
ldapsearch -x \
  -H ldap://localhost \
  -D 'administrator@LAB.INTERNAL' \
  -w 'Admin.1.samba' \
  -b 'dc=lab,dc=internal' \
  '(objectClass=domainDNS)' \
  lockoutDuration lockoutThreshold lockOutObservationWindow
```

### Check lockout state of a user

```bash
ldapsearch -x \
  -H ldap://localhost \
  -D 'administrator@LAB.INTERNAL' \
  -w 'Admin.1.samba' \
  -b 'dc=lab,dc=internal' \
  '(sAMAccountName=testuser)' \
  lockoutTime badPwdCount userAccountControl msDS-User-Account-Control-Computed
```

### List all users

```bash
ldapsearch -x \
  -H ldap://localhost \
  -D 'administrator@LAB.INTERNAL' \
  -w 'Admin.1.samba' \
  -b 'cn=Users,dc=lab,dc=internal' \
  '(objectClass=user)' \
  sAMAccountName mail userAccountControl
```

### Test LDAP authentication as a user

```bash
ldapsearch -x \
  -H ldap://localhost \
  -D 'testuser@LAB.INTERNAL' \
  -w 'testuser.1.Samba' \
  -b 'dc=lab,dc=internal' \
  -s base '(objectClass=*)' dn
```

---

## Useful Commands

```bash
# List all users
docker exec samba-ad-dc samba-tool user list

# Create a new user
docker exec samba-ad-dc samba-tool user create myuser 'Myuser.1.samba'

# Unlock a locked user
docker exec samba-ad-dc samba-tool user unlock testuser

# Show password/lockout policy
docker exec samba-ad-dc samba-tool domain passwordsettings show

# Check domain health
docker exec samba-ad-dc samba-tool domain info 127.0.0.1

# View Samba config
docker exec samba-ad-dc testparm -s

# Follow container logs
docker compose logs -f
```

---

## Directory Tree (LDAP)

```
RootDSE
└── DC=lab,DC=internal              ← domain object (lockout policy lives here)
    ├── CN=Users
    │   ├── CN=Administrator
    │   ├── CN=testuser
    │   ├── CN=jdoe
    │   ├── CN=jsmith
    │   ├── CN=locktest
    │   └── CN=TestUsers            ← group
    ├── CN=Computers
    ├── CN=Builtin
    └── CN=Configuration,DC=lab,DC=internal
```

---

## Data Persistence

Samba data is stored in Docker named volumes:
- `samba-data` → `/var/lib/samba` (AD database, DNS, secrets)
- `samba-config` → `/etc/samba` (configuration)

To start completely fresh:

```bash
docker compose down -v   # removes volumes
docker compose up -d --build
```

---

## Ports

| Port  | Protocol | Service              | Host Mapping |
|-------|----------|----------------------|--------------|
| 53    | TCP/UDP  | DNS                  | 5300         |
| 88    | TCP/UDP  | Kerberos             | 88           |
| 389   | TCP/UDP  | LDAP                 | 389          |
| 636   | TCP      | LDAPS                | 636          |
| 445   | TCP      | SMB                  | 445          |
| 464   | TCP/UDP  | Kerberos kpasswd     | 464          |
| 3268  | TCP      | Global Catalog       | 3268         |
| 3269  | TCP      | Global Catalog SSL   | 3269         |

> DNS is mapped to host port **5300** to avoid conflicts with macOS's built-in mDNSResponder on port 5353.

---

## Limitations
- **No TLS by default** — this setup is intended for local development. Do not expose to untrusted networks.
- **Single DC** — no multi-DC replication. Suitable for development, not production.

---

## License

[MIT](LICENSE)
