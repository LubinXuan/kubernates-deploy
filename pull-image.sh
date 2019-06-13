V=v1.14.2
D=hub.worken.cn


function pull()
{
	echo "pull image:"$1"  version:"$2"   from:"$3
	docker pull $3/$1:$2
	docker tag $3/$1:$2 $D/$1:$2
	docker push $D/$1:$2
#	docker rmi $3/$1:$2
}

pull fluentd-elasticsearch v2.4.0 mirrorgooglecontainers

pull metrics-server-amd64 v0.3.3 mirrorgooglecontainers

pull kubernetes-dashboard v1.10.1 registry.cn-hangzhou.aliyuncs.com/xuanlb

pull flannel v0.11.0-amd64 quay.io/coreos
pull pause 3.1 mirrorgooglecontainers
pull coredns 1.3.1 coredns

images=(kube-apiserver kube-controller-manager kube-scheduler kube-proxy)
for image in ${images[@]}; do
	echo $image
	pull $image $V mirrorgooglecontainers
done
