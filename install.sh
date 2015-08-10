#!/bin/bash

if [ $EUID -ne 0 ]; then
    echo "Using sudo to continue."
    case $0 in
        bash)
            sudo $0 -s $*
            ;;
        *)
            sudo bash $0 $*
            ;;
    esac
    exit 0
fi

echo 'millhouse' > /etc/hostname
hostname -F /etc/hostname

echo "Install GitLab."
curl -Lso /tmp/gitlab-ce.deb https://packages.gitlab.com/gitlab/gitlab-ce/packages/debian/wheezy/gitlab-ce_7.13.3-ce.1_amd64.deb/download
dpkg -i /tmp/gitlab-ce.deb

echo "Setting GitLab."
ip=$(curl ipv4.icanhazip.com)
sed -e "s#^external_url .*#external_url 'http://$ip:10080'#" -i /etc/gitlab/gitlab.rb
echo "gitlab_rails['gitlab_ssh_host'] = '$ip:10022'" >> /etc/gitlab/gitlab.rb
echo "ci_external_url 'http://$ip:18181'" >> /etc/gitlab/gitlab.rb

gitlab-ctl reconfigure

echo "Update repository."
apt-get update -qq

echo "Install dependencies."
DEBIAN_FRONTEND=nointeractive apt-get install -qq docker.io postfix openssh-server nis rpcbind

echo "Setting GitLabCI service."
cat > /etc/systemd/system/gitlab-ci-docker.service << EOF
[Unit]
Description=GitlabCI runner in docker
After=docker.service
Requires=docker.service

[Service]
Restart=always
ExecStartPre=-/usr/bin/docker rm gitlab-runner
ExecStart=/usr/bin/docker run --rm \
    --name gitlab-runner \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume /srv/gitlab-runner:/etc/gitlab-runner \
    gitlab/gitlab-runner
ExecStop=/usr/bin/docker stop gitlab-runner

[Install]
WantedBy=local.target
EOF

systemctl start gitlab-ci-docker.service

echo "Setting NIS."
sed -e 's/^NISSERVER=.*/NISSERVER=master/' -e 's/^NISCLIENT=.*/NISCLIENT=false/' -i /etc/default/nis

sudo service rpcbind restart
sudo service nis restart
/usr/lib/yp/ypinit -m < /dev/null
