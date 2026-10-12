#!/bin/bash
set -euxo pipefail

rm -f /etc/machine-id
echo uninitialized > /etc/machine-id
rm -f /var/lib/systemd/random-seed

# An empty password, as on the Arch live image: the secondary consoles are root recovery shells.
passwd -d root

systemctl enable NetworkManager.service
systemctl set-default multi-user.target
