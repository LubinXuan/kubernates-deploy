for i in 1 2;do
  ip="k8s-node-"$i
  echo "清理工作节点--->"$ip
  ssh $ip "
      kubeadm reset -f;
      rm -rf /var/lib/cni;
      rm -rf /var/lib/kubelet;
      rm -rf /etc/cni;
      rm -rf /etc/kubernetes;
      rm ~/.kube -rf;
      mkdir -p /etc/kubernetes/pki/etcd;
      mkdir -p ~/.kube/; 
      ipvsadm --clear;
      ifconfig cni0 down;
      ifconfig flannel.1 down;
      ifconfig docker0 down;
      ip link delete flannel.1;
      ip link delete cni0;
  "
done
