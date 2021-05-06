#!/bin/bash

echo "This Script is made to set 3 node cluster with 1 master and 2 slave"
echo -e "\e[33mINSTRUCTION\e[0m::\n\e[32mOs and Version :: CentOS Linux release 7.4.1708 (Core)\nPlease disable selinux"
echo -e "Please run this script on master server only\nThis script will set passwordless authentication set from Master server to all Slave server\nPlease run as a root user with same password\e[0m"
read -p "Please provide master ip:: " Mip
read -p "Please provide Slave 1 ip:: " Sip1
read -p "Please provide Slave 2 ip:: " Sip2
read -p "Please provide the root password:: " RootP

yum install sshpass.x86_64 -y
ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa <<< y

for each_ip in ${Mip} ${Sip1} ${Sip2}
do
sshpass -p${RootP} ssh-copy-id ${each_ip} -o StrictHostKeyChecking=no
done

Mhostnm=$(hostname)
S1hostnm=$(ssh ${Sip1} "hostname")
S2hostnm=$(ssh ${Sip2} "hostname")

all_kube_server ()
{
for each in ${Mip} ${Sip1} ${Sip2}
do
ssh ${each} $1
done
}

#all_kube_server "cat <<EOF>> /etc/hosts
#${Mip} ${Mhostnm} node1
#${Sip1} ${S1hostnm} node2
#${Sip2} ${S2hostnm} node3
#EOF"

all_kube_server "echo '${Mip} ${Mhostnm} node1' >> /etc/hosts"
all_kube_server "echo '${Sip1} ${S1hostnm} node2' >> /etc/hosts"
all_kube_server "echo '${Sip2} ${S2hostnm} node3' >> /etc/hosts"

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

for each in ${Sip1} ${Sip2}
do
scp /etc/yum.repos.d/kubernetes.repo ${each}:/etc/yum.repos.d/kubernetes.repo
done

for each in "6443/tcp" "2379-2380/tcp" "10250/tcp" "10251/tcp" "10252/tcp" "10255/tcp"
do
  firewall-cmd --permanent --add-port=${each}
done
firewall-cmd  --reload

for each in ${Sip1} ${Sip2}
do
   for port_no in "6783/tcp" "10250/tcp" "10255/tcp" "30000-32767/tcp"
   do
     ssh ${each} "firewall-cmd --permanent --add-port=${port_no}"
   done
   ssh ${each} "firewall-cmd  --reload"
done

all_kube_server "modprobe br_netfilter"
all_kube_server "echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables"
all_kube_server "sudo yum install -y yum-utils"
all_kube_server "sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo"
all_kube_server "sudo yum install docker-ce docker-ce-cli containerd.io -y"
all_kube_server "sudo systemctl enable docker"
all_kube_server "sudo systemctl start docker"
all_kube_server "swapoff -a"
all_kube_server "sed -i.back$(date +'%y%m%d') '/swap/c #' /etc/fstab"
all_kube_server "yum install kubeadm -y"
all_kube_server "systemctl enable kubelet"
all_kube_server "systemctl start kubelet"

kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
echo 'source <(kubectl completion bash)' >> /etc/bashrc
echo 'source <(kubeadm completion bash)' >> /etc/bashrc
source /etc/bashrc

export kubever=$(kubectl version | base64 | tr -d '\n')
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$kubever"
worker_join_token=$(kubeadm token create --print-join-command)
for each in ${Sip1} ${Sip2}
do 
ssh ${each} '${worker_join_token}'
done
clear
kubectl get nodes
