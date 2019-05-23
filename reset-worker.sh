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
      ipvsadm --clear
  "
done
