#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

yum install --nogpgcheck --quiet -y -e 0 epel-release

PACKAGES=(
    bind-utils
    net-tools
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"

ln -sf /usr/share/zoneinfo/Europe/Brussels /etc/localtime
systemctl enable firewalld
systemctl start  firewalld