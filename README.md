# crio-krun

Container image to run CRI-O in a nested container setup, with krun enabled for microVM isolation.

## Usage

Rootful `--privileged` mode is required to manage containers and/or microVMs.

```bash
sudo podman run --privileged \
    --tmpfs /run \
    -v /run/crio:/var/run/crio \
    -v crio-graph-root:/var/lib/containers \
    --name crio --rm --replace \
    crio-krun
```

## Motivation

This project was developed to run [k0s](https://docs.k0sproject.io/stable/) worker nodes on multi-tenant servers with rootful container engines. While k0s offers a minimal and efficient Kubernetes distribution, a system-level installation can be challenging to manage on multi-tenant servers due to potential interference with other users' workloads. Running k0s within a container provides improved manageability in such environments.

k0s provides official images for deployment with Docker and other container engines; however, these configurations rely on k0s's embedded containerd CRI implementation. This project enables the use of [CRI-O](https://github.com/cri-o/cri-o) and [krun](https://github.com/containers/libkrun) instead, offering enhanced isolation through microVM technology.

## k0s + crio-krun

The following compose file demonstrates a complete k0s + crio-krun configuration:

```yaml
services:
  zerotier:
    hostname: ${K0S_NODE_NAME}
    image: docker.io/zerotier/zerotier:latest
    devices:
      - /dev/net/tun:/dev/net/tun:rwm
    cap_add:
      - NET_ADMIN
    restart: always
    environment:
      - ZEROTIER_IDENTITY_PUBLIC=${ZT_ID_PUB}
      - ZEROTIER_IDENTITY_SECRET=${ZT_ID_SEC}
    command: ${ZT_NET}
    healthcheck:
      test: 
        - "CMD-SHELL"
        - "zerotier-cli listnetworks | grep -E 'OK.*[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' || exit 1"
      retries: 15
      start_interval: 3s
      start_period: 15s
      interval: 15s
    ports:
      - "9994:9993/udp"
  crio-krun:
    depends_on:
      zerotier:
        condition: service_healthy
        restart: true
    restart: always
    image: ghcr.io/chaserhkj/crio-krun:latest
    network_mode: service:zerotier
    privileged: true
    volumes:
      - crio-data:/var/lib/containers
      - cni-config:/etc/cni
      - k0s-log:/var/log/pods
      - crio-run:/var/run/crio
      - k0s-run:/run/k0s
      - ./k0s-data:/var/lib/k0s:shared
  k0s:
    depends_on:
      - crio-krun
    restart: always
    image: docker.io/k0sproject/k0s:${K0S_VERSION}
    tmpfs: ["/run"]
    privileged: true
    network_mode: service:zerotier
    command:
      - k0s
      - worker
      - ${K0S_JOIN_TOKEN}
      - --cri-socket=remote:unix:///run/crio/crio.sock
      - --kubelet-extra-args=--node-ip=${K0S_NODE_IP}
    volumes:
      - cni-config:/etc/cni
      - k0s-log:/var/log/pods
      - crio-run:/var/run/crio
      - k0s-run:/run/k0s
      - ./k0s-data:/var/lib/k0s:shared
volumes:
  crio-data: {}
  cni-config: {}
  k0s-log: {}
  crio-run:
    driver_opts:
      type: tmpfs
      device: tmpfs
  k0s-run:
    driver_opts:
      type: tmpfs
      device: tmpfs
networks:
  default:
    driver: bridge
```

[ZeroTier](https://github.com/zerotier/ZeroTierOne) is included in this configuration because the clusters are deployed using ZeroTier as a mesh networking solution. This setup confines the entire worker node within the pod, ensuring that no routes or IP addresses are leaked to the host or other container workloads running on the host.

## Limitations

A known limitation of this approach relates to metric collection. Since kubelet and the container runtime operate in separate cgroup and PID namespaces, kubelet cannot retrieve resource usage information from either the pods it manages or from other workloads running on the host. This limitation may affect horizontal autoscaling functionality within the Kubernetes cluster.

The official k0s in-container solution experiences a similar issue, though it is marginally better since kubelet running in the same container as the pod workloads can at least access metrics for the pods it directly manages. Metrics for the entire host remain inaccessible in both approaches.

A workaround involves using `cgroup: host` and `pid: host` on the k0s container, which enables kubelet to report metrics for the entire host. However, due to a [k0s issue](https://github.com/k0sproject/k0s/issues/4234), these settings cause kubelet and k0s worker processes to escape the container cgroup. This means stopping the container will not terminate these processes; they must be killed manually through systemd on systemd-based systems or via cgroup.kill.

A more robust solution involves deploying a Prometheus node exporter in a sidecar container to collect metrics, then using prometheus-adapter to provide the metrics API to cluster autoscalers instead of the Kubernetes Metrics Server. This approach requires a complete Prometheus deployment and significant modifications to the k0s stack itself.

## Disclaimer

This README file is enhanced using [MiniMax-M2.5](https://huggingface.co/MiniMaxAI/MiniMax-M2.5) and [Continue](https://www.continue.dev/).
