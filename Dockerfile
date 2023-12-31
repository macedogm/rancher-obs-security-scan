#!BuildTag: security-scan:latest

# Final micro image
FROM bci/bci-micro:15.5 AS micro

# Temporary build stage
FROM bci/golang:1.21 AS builder

# Define build arguments
ARG kube_bench_version=0.6.17
ARG sonobuoy_version=0.56.16
ARG kubectl_version=1.28.0
ARG ARCH=amd64


COPY . /kb-summarizer
WORKDIR /kb-summarizer
RUN CGO_ENABLED=0 go build -ldflags "-extldflags -static -s" \
    -o kb-summarizer cmd/kb-summarizer/main.go

# Install system packages using builder image that has zypper 
COPY --from=micro / /chroot/

## Install kubectl into micro
#RUN curl -Lo /chroot/usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/v${kubectl_version}/bin/linux/${ARCH}/kubectl" && chmod +x /chroot/usr/local/bin/kubectl

## Install Sonobuoy into micro
#RUN curl -sLf "https://github.com/vmware-tanzu/sonobuoy/releases/download/v${sonobuoy_version}/sonobuoy_${sonobuoy_version}_linux_${ARCH}.tar.gz" | tar -xvzf - -C /chroot/usr/bin sonobuoy

## Install kube-bench into micro
#RUN curl -sLf "https://github.com/aquasecurity/kube-bench/releases/download/v${kube_bench_version}/kube-bench_${kube_bench_version}_linux_${ARCH}.tar.gz" | tar -xvzf - -C /chroot/usr/bin

## Copy the files within /cfg straight from the immutable GitHub source to /etc/kube-bench/cfg/ into micro
#RUN mkdir -p /chroot/etc/kube-bench/ && \
#    curl -sLf "https://github.com/aquasecurity/kube-bench/archive/refs/tags/v${kube_bench_version}.tar.gz" | \
#    tar xvz -C /chroot/etc/kube-bench/ --strip-components=1 "kube-bench-${kube_bench_version}/cfg"

## OS binaries to run kube-bench audit commands
RUN zypper --installroot /chroot -n --gpg-auto-import-keys up
RUN zypper --installroot /chroot -n in --no-recommends systemd || if chroot /chroot/ journalctl --no-pager --version; then true; else false; fi
RUN zypper --installroot /chroot -n in --no-recommends findutils tar jq gawk diffutils procps gzip curl
RUN zypper --installroot /chroot clean -a && \
    rm -rf /chroot/var/cache/zypp/* /chroot/var/log/zypp/*

# Main stage using bco-mirco as the base image
FROM micro

# Copy binaries and configuration files from builder to micro
COPY --from=builder /chroot/ /

## Copy binaries and configuration files from the local repository to micro
COPY --from=builder --chmod=755 /kb-summarizer/kb-summarizer /usr/bin/
COPY package/cfg/ /etc/kube-bench/cfg/
COPY --chmod=755 package/run.sh \
     package/run_sonobuoy_plugin.sh \
     package/helper_scripts/check_files_permissions.sh \
     package/helper_scripts/check_files_owner_in_dir.sh \
     package/helper_scripts/check_encryption_provider_config.sh \
     package/helper_scripts/check_for_network_policies.sh \
     package/helper_scripts/check_for_default_sa.sh \
     package/helper_scripts/check_for_default_ns.sh \
     package/helper_scripts/check_for_k3s_etcd.sh \
     package/helper_scripts/check_for_rke2_network_policies.sh \
     package/helper_scripts/check_for_rke2_cni_net_policy_support.sh \
     package/helper_scripts/check_cafile_permissions.sh \
     package/helper_scripts/check_cafile_ownership.sh \
     /usr/bin/

CMD ["run.sh"]
