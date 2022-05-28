#!/bin/sh
# SSH server configuration

SSHD_CONFDIR='/etc/ssh'
SSHD_INCLUDE_CONFDIR="${SSHD_CONFDIR}/conf.d"
SSHD_CONF_FILE="${SSHD_CONFDIR}/sshd_config"

SSHD_SYSTEM_AUTH_KEYS_DIR='/etc/ssh/authorized_keys'
SSHD_HOST_KEY_TYPES='rsa ed25519'

sshd_setup() {
    dodir_mode "${TARGET_ROOTFS:?}/${SSHD_CONFDIR}" 0755 '0:0' || return
    dodir_mode "${TARGET_ROOTFS:?}/${SSHD_INCLUDE_CONFDIR}" 0700 '0:0' || return
    dodir_mode "${TARGET_ROOTFS:?}/${SSHD_SYSTEM_AUTH_KEYS_DIR}" 0710 "0:${OCONF_SSHD_GID_LOGIN:-0}" || return
    dofile "${TARGET_ROOTFS:?}/${SSHD_CONF_FILE}" 0600 '0:0' gen_sshd_config || return
    sshd_setup_create_host_keys || return
}


sshd_setup_create_host_keys() {
    local key_type
    local key_file

    autodie find "${TARGET_ROOTFS:?}/${SSHD_CONFDIR}" \
        -mindepth 1 -maxdepth 1 \
        -type f \
        \( -name 'ssh_host_*_key' -or -name 'ssh_host_*_key.pub' \) \
        -delete

    for key_type in ${SSHD_HOST_KEY_TYPES:?}; do
        key_file="${TARGET_ROOTFS:?}/${SSHD_CONFDIR}/ssh_host_${key_type}_key"

        set -- -N '' -C "root@${OCONF_HOSTNAME:-staging}" -t "${key_type}" -f "${key_file}"

        case "${key_type}" in
            'rsa') set -- "${@}" -b '4096' ;;
        esac

        autodie ssh-keygen "${@}"
    done
}


gen_sshd_config() {
    local iter

cat << EOF
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512
MACs hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
#KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com

EOF

for iter in ${SSHD_HOST_KEY_TYPES:?}; do
    printf 'HostKey %s/ssh_host_%s_key\n' "${SSHD_CONFDIR}" "${iter}"
done

cat << EOF

AllowGroups ${OCONF_SSHD_GROUP_LOGIN:?}
PermitRootLogin no

PermitEmptyPasswords no

# Public Key Auth w/o PAM
AuthenticationMethods publickey
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no

## # PAM Auth for 2FA
## AuthenticationMethods publickey,keyboard-interactive:pam
## PubkeyAuthentication yes
## PasswordAuthentication no
## ChallengeResponseAuthentication yes
## UsePAM yes

AuthorizedKeysFile  ${SSHD_SYSTEM_AUTH_KEYS_DIR}/%u

GatewayPorts no
PermitTunnel no

AllowAgentForwarding no
AllowTcpForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
X11Forwarding no
PermitTTY no
PermitUserEnvironment no
PermitUserRC no

Banner none
PrintLastLog no
PrintMotd no

TCPKeepAlive yes
UseDNS no

Subsystem sftp internal-sftp

Include ${SSHD_INCLUDE_CONFDIR}/*.conf

Match Group ${OCONF_SSHD_GROUP_SHELL:?}
    PermitTTY yes

Match Group ${OCONF_SSHD_GROUP_FORWARDING:?}
    AllowTcpForwarding yes
EOF
}


if feat_all "${OFEAT_SSHD_CONFIG:-0}"; then
    print_action "Creating SSH server configuration"
    sshd_setup
fi
