#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"

yum install --nogpgcheck --quiet -y -e 0 "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"

PACKAGES=(
    "postgresql${PGVER}"
    "postgresql${PGVER}-server"
    "postgresql${PGVER}-contrib"
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"
firewall-cmd --quiet --permanent --add-service=postgresql
firewall-cmd --quiet --reload