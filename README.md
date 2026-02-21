# crio-krun

Container image to run cri-o in a nested container setup, with krun enabled for microVM isolation

## Usage

Rootful `--privileged` is required to manage containers and/or microVMs.

```bash
sudo podman run --privileged \
    --tmpfs /run \
    -v /run/crio:/var/run/crio \
    -v crio-graph-root:/var/lib/containers \
    --name crio --rm --replace \
    crio-krun
```

## But why ?

I built this mostly for running [k0s](https://docs.k0sproject.io/stable/) worker node on multi-tenant servers with rootful container engines. While k0s is cool and minimal, a system-level installation of it is tricky to manage on multi-tenant servers as it could easily interfere with the loads of other the users of the server. Running it in a container helps managing these a lot.

k0s does provide official images to be run with docker or other container engines, but running it this way it can only use its embedded containerd CRI. I want to use [CRI-O](https://github.com/cri-o/cri-o) and [krun](https://github.com/containers/libkrun) for the better isolation provided by the microVM, so I tried and eventually made this work.

## k0s + crio-krun

Here is my compose file for k0s + crio-krun setup, for reference:

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

I put [zerotier](https://github.com/zerotier/ZeroTierOne) in since my clusters are set up using zerotier as mesh network. With this setup the entire worker node is confined within this pod and no routes or ips will be leaked to the host or other container loads on the host.

## limitations

One known limitations of this approach is that since kubelet and container runtime is run in different cgroup and pid namespaces, kubelet's metric collection won't be able to see any usage, neither from the pods it started itself, or from the other loads on the host. This may complicate horizontal autoscaling in the k8s cluster.

The official k0s running in container solution has a similar limitation, but it is slightly better since kubelet running in the same container as the pod loads would at least enable it to see metrics of the pods it started itself. Metrics for the entire host is still not possible.

A workaround for this is to use `cgroup: host` and `pid: host` on the k0s container. This gives kubelet the ability to report metrics of entire host. Just be aware that due to this [k0s issue](https://github.com/k0sproject/k0s/issues/4234), under this setting, kubelet and k0s worker process will escape container cgroup (i.e. stopping the container won't stop these processes, you need to manually kill them either by systemd on a systemd system or by cgroup.kill)

A more proper solution is to use prometheus node exporter to collect the metrics on another sidecar container and use prometheus-adapter to provide metrics API instead of k8s metrics server to the cluster auto scalers. But this requires a full prometheus setup and a lot of changes to the k8s stack itself.
