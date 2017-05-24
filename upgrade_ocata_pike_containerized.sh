#!/bin/bash

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

    # master repos
    cd /home/stack/ && source stackrc

    sudo curl -L -o /etc/yum.repos.d/delorean.repo https://trunk.rdoproject.org/centos7-master/current-passed-ci/delorean.repo
    sudo curl -L -o /etc/yum.repos.d/delorean-current.repo https://trunk.rdoproject.org/centos7/current/delorean.repo
    sudo sed -i 's/\[delorean\]/\[delorean-current\]/' /etc/yum.repos.d/delorean-current.repo
    sudo /bin/bash -c "cat <<EOF>>/etc/yum.repos.d/delorean-current.repo
includepkgs=diskimage-builder,instack,instack-undercloud,os-apply-config,os-collect-config,os-net-config,os-refresh-config,python-tripleoclient,openstack-tripleo-common*,openstack-tripleo-heat-templates,openstack-tripleo-image-elements,openstack-tripleo,openstack-tripleo-puppet-elements,openstack-puppet-modules,openstack-tripleo-ui,puppet-*
EOF"
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
}
function upgrade_overcloud
{
    echo -e "\x1B[01;96m Upgrade overcloud \n / \x1B[0m"
    echo -e "\x1B[01;96m ------------------------------------------------------------------ \x1B[0m"
    cd /home/stack/ && source stackrc
    export THT=/usr/share/openstack-tripleo-heat-templates
    openstack overcloud deploy \
    --libvirt-type qemu \
    --ntp-server clock.redhat.com \
    --control-scale 1 \
    --templates $THT \
    -e $THT/environments/low-memory-usage.yaml \
    -e $THT/environments/docker.yaml \
    -e $THT/environments/major-upgrade-composable-steps-docker.yaml \
    -e ~/containers-default-parameters.yaml
    sleep 3
    printf "\n"
}


function main
{
    upgrade_undercloud_node
    perform_preparing_steps
    download_docker_images_to_local_registry
    upgrade_overcloud
}
main $@

