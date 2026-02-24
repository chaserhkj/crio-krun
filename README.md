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

[This compose file](examples/k0s/compose.yaml) demonstrates a complete k0s + crio-krun configuration.

[ZeroTier](https://github.com/zerotier/ZeroTierOne) is included in this configuration because the clusters are deployed using ZeroTier as a mesh networking solution. This setup confines the entire worker node within the pod, ensuring that no routes or IP addresses are leaked to the host or other container workloads running on the host.

[node-exporter](https://github.com/prometheus/node_exporter) is included in this configuration to mitigate the limitation mentioned below.

## Limitations

A known limitation of this approach relates to metric collection. Since kubelet and the container runtime operate in separate cgroup and PID namespaces, kubelet cannot retrieve resource usage information from either the pods it manages or from other workloads running on the host. This limitation may affect horizontal autoscaling functionality within the Kubernetes cluster.

The official k0s in-container solution experiences a similar issue, though it is marginally better since kubelet running in the same container as the pod workloads can at least access metrics for the pods it directly manages. Metrics for the entire host remain inaccessible in both approaches.

A workaround involves using `cgroup: host` and `pid: host` on the k0s container, which enables kubelet to report metrics for the entire host. However, due to a [k0s issue](https://github.com/k0sproject/k0s/issues/4234), these settings cause kubelet and k0s worker processes to escape the container cgroup. This means stopping the container will not terminate these processes; they must be killed manually through systemd on systemd-based systems or via cgroup.kill.

A more robust solution involves deploying a Prometheus node exporter in a sidecar container to collect metrics, then using prometheus-adapter to provide the metrics API to cluster autoscalers instead of the Kubernetes Metrics Server. This approach requires a complete Prometheus deployment and modifications to the k0s stack itself (`--disable-components metrics-server`).

Furthermore, to collect accurate per-pod metrics, a [cAdvisor](https://github.com/google/cadvisor) instance could be deployed to run in CRI-O runtime with proper bind mounts to access and export these metrics. See [this file](examples/k0s/cAdvisor.yaml) for details.

## Disclaimer

This README file is enhanced using [MiniMax-M2.5](https://huggingface.co/MiniMaxAI/MiniMax-M2.5) and [Continue](https://www.continue.dev/).
