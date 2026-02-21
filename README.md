# crio-krun

Container image to run cri-o in a nested container setup, with krun enabled for microVM isolation

Rootful `--privileged` is required to manage containers and/or microVMs.

```bash
sudo podman run --privileged \
    --tmpfs /run \
    -v /run/crio:/var/run/crio \
    -v crio-graph-root:/var/lib/containers \
    --name crio --rm --replace \
    crio-krun
```
