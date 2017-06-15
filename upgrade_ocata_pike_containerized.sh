#!/bin/bash

function deploy_overcloud
{
    echo -e "\x1B[01;96m Deploy overcloud \n / \x1B[0m"
    echo -e "\x1B[01;96m ------------------------------------------------------------------ \x1B[0m"
    cd /home/stack/ && source stackrc
    export THT=/usr/share/openstack-tripleo-heat-templates
    openstack overcloud deploy \
    --libvirt-type qemu \
    --ntp-server clock.redhat.com \
    --control-scale 1 \
    --control-flavor oooq_control \
    --compute-flavor oooq_compute \
    --templates $THT \
    -e $THT/environments/low-memory-usage.yaml \
    -e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation.yaml \
    -e /usr/share/openstack-tripleo-heat-templates/environments/net-single-nic-with-vlans.yaml \
    -e /usr/share/openstack-tripleo-heat-templates/environments/network-environment.yaml 
    sleep 3
    printf "\n"
}

function download_docker_images_to_local_registry
{
    echo -e "\x1B[01;96m Create and download latest openstack images to local registry\n / \x1B[0m"
    echo -e "\x1B[01;96m ------------------------------------------------------------------ \x1B[0m"
    cd /home/stack/ && source stackrc
    sudo openstack overcloud container image upload --verbose --config-file /usr/share/tripleo-common/container-images/overcloud_containers.yaml
    sleep 3
    printf "\n"
}


function upgrade_undercloud_node
{
    echo -e "\x1B[01;96m Upgrade undercloud node\n / \x1B[0m"
    echo -e "\x1B[01;96m ------------------------------------------------------------------ \x1B[0m"
    ### UPGRADE UNDERCLOUD ###
    
    #w/a https://bugs.launchpad.net/tripleo/+bug/1692899
    controller_ip="$(nova list|grep controller|grep ctlplane|awk -F' ' '{ print $12 }'|awk -F'=' '{ print $2 }')" 
    ssh -o StrictHostKeyChecking=no heat-admin@$controller_ip "cd /tmp/; git clone https://github.com/levor23/etc/"
    ssh -o StrictHostKeyChecking=no heat-admin@$controller_ip "sudo yum install -y patch"
    ssh -o StrictHostKeyChecking=no heat-admin@$controller_ip "sudo patch /usr/libexec/os-refresh-config/configure.d/50-heat-config-docker-cmd /tmp/etc/patch_for_docker_cmd"
    
    # master repos
    cd /home/stack/ && source stackrc

    sudo curl -L -o /etc/yum.repos.d/delorean.repo https://trunk.rdoproject.org/centos7-master/current-passed-ci/delorean.repo
    sudo curl -L -o /etc/yum.repos.d/delorean-current.repo https://trunk.rdoproject.org/centos7/current/delorean.repo
    sudo sed -i 's/\[delorean\]/\[delorean-current\]/' /etc/yum.repos.d/delorean-current.repo
    sudo /bin/bash -c 'printf "\nincludepkgs=diskimage-builder,instack,instack-undercloud,os-apply-config,os-collect-config,os-net-config,os-refresh-config,python-tripleoclient,openstack-tripleo-common*,openstack-tripleo-heat-templates,openstack-tripleo-image-elements,openstack-tripleo,openstack-tripleo-puppet-elements,openstack-puppet-modules,openstack-tripleo-ui,puppet-*" >> /etc/yum.repos.d/delorean-current.repo'
    sudo curl -L -o /etc/yum.repos.d/delorean-deps.repo https://trunk.rdoproject.org/centos7/delorean-deps.repo
    
    sudo systemctl stop openstack-*
    sudo systemctl stop neutron-*
    sudo systemctl stop httpd

    sudo yum -y update instack-undercloud openstack-puppet-modules openstack-tripleo-common python-tripleoclient
    

    openstack undercloud upgrade
    printf "\n"
}

function perform_preparing_steps
{
    echo -e "\x1B[01;96m Perform some preparatory steps\n / \x1B[0m"
    echo -e "\x1B[01;96m ------------------------------------------------------------------ \x1B[0m"

    # create an envrionment file to make overcloud fetch the images from the undercloud
    # (192.168.24.1 is undercloud IP that must be pingable from the overcloud)
    echo > ~/containers-default-parameters.yaml 'parameter_defaults:
      DockerNamespace: 192.168.24.1:8787/tripleoupstream
      DockerNamespaceIsRegistry: true
    '
    sleep 3
    printf "\n"
    
    cat > ~/containers-upgrade-repos.yaml <<'EOEF'
parameter_defaults:
  UpgradeInitCommand: |
    set -ex
    pushd /etc/yum.repos.d/
    rm -rf delorean*
    REPO_PREFIX=/etc/yum.repos.d
    DELOREAN_REPO_URL=https://trunk.rdoproject.org/centos7/current-tripleo
    DELOREAN_REPO_FILE=delorean.repo

    sudo curl -Lvo $REPO_PREFIX/delorean-deps.repo https://trunk.rdoproject.org/centos7/delorean-deps.repo
    sudo sed -i -e 's%priority=.*%priority=30%' $REPO_PREFIX/delorean-deps.repo
    cat $REPO_PREFIX/delorean-deps.repo

    # Enable last known good RDO Trunk Delorean repository
    sudo curl -Lvo $REPO_PREFIX/delorean.repo $DELOREAN_REPO_URL/$DELOREAN_REPO_FILE
    sudo sed -i -e 's%priority=.*%priority=20%' $REPO_PREFIX/delorean.repo
    cat $REPO_PREFIX/delorean.repo

    # Enable latest RDO Trunk Delorean repository
    sudo curl -Lvo $REPO_PREFIX/delorean-current.repo https://trunk.rdoproject.org/centos7/current/delorean.repo
    sudo sed -i -e 's%priority=.*%priority=10%' $REPO_PREFIX/delorean-current.repo
    sudo sed -i 's/\[delorean\]/\[delorean-current\]/' $REPO_PREFIX/delorean-current.repo
    sudo /bin/bash -c "cat <<-EOF>>$REPO_PREFIX/delorean-current.repo

    includepkgs=diskimage-builder,instack,instack-undercloud,os-apply-config,os-collect-config,os-net-config,os-refresh-config,python-tripleoclient,openstack-tripleo-common*,openstack-tripleo-heat-templates,openstack-tripleo-image-elements,openstack-tripleo,openstack-tripleo-puppet-elements,openstack-puppet-modules,openstack-tripleo-ui,puppet-*
    EOF"
    cat $REPO_PREFIX/delorean-current.repo
    popd
    yum clean all
EOEF
}

function upgrade_overcloud
{
    echo -e "\x1B[01;96m Upgrade overcloud \n / \x1B[0m"
    echo -e "\x1B[01;96m ------------------------------------------------------------------ \x1B[0m"
    cd /home/stack/ && source stackrc
    export THT=/usr/share/openstack-tripleo-heat-templates
    #workaround for VLAN 10 rules
    ./overcloud-prep-network.sh
    openstack overcloud deploy \
    --libvirt-type qemu \
    --ntp-server clock.redhat.com \
    --control-scale 1 \
    --control-flavor oooq_control \
    --compute-flavor oooq_compute \
    --templates $THT \
    -e $THT/environments/low-memory-usage.yaml \
    -e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation-v6.yaml \
    -e /usr/share/openstack-tripleo-heat-templates/environments/net-single-nic-with-vlans-v6.yaml \
    -e /usr/share/openstack-tripleo-heat-templates/environments/network-environment.yaml \
    -e $THT/environments/docker.yaml \
    -e $THT/environments/major-upgrade-composable-steps-docker.yaml \
    -e ~/containers-default-parameters.yaml \
    -e ~/containers-upgrade-repos.yaml 
    sleep 3
    printf "\n"
}


function main
{
    deploy_overcloud
    upgrade_undercloud_node
    perform_preparing_steps
    download_docker_images_to_local_registry
    upgrade_overcloud
}
main $@

