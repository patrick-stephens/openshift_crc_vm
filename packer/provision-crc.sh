#!/bin/bash
set -eux

OPENSHIFT_PULL_SECRET=${OPENSHIFT_PULL_SECRET:-$HOME/.config/crc/pull-secret.txt}
if [[ ! -f "$OPENSHIFT_PULL_SECRET" ]]; then
    echo "ERROR: Missing Openshift pull secret file: $OPENSHIFT_PULL_SECRET"
    exit 1
fi

sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y qemu-kvm libvirt-daemon libvirt-daemon-system network-manager
sudo systemctl disable --now systemd-networkd
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now libvirtd

curl -sSfLO https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/crc/latest/crc-linux-amd64.tar.xz
tar -xvf crc-linux-amd64.tar.xz
sudo cp -vf crc-linux-*-amd64/crc /usr/local/bin/
sudo chmod a+x /usr/local/bin/crc

/usr/local/bin/crc config set pull-secret-file "$OPENSHIFT_PULL_SECRET"
/usr/local/bin/crc config set kubeadmin-password admin
/usr/local/bin/crc config set consent-telemetry no
/usr/local/bin/crc config set disable-update-check true
/usr/local/bin/crc config set network-mode user
echo "Completed provisioning"
