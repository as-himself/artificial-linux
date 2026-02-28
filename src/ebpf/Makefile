# Artificial Linux - eBPF programs (monitor + gatekeeper)
# Requires: clang, libbpf, linux kernel headers with BTF

CLANG ?= clang
LLC ?= llc
ARCH := $(shell uname -m)
KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
BPF_CFLAGS := -I. -I$(KERNEL_SRC)/include -I$(KERNEL_SRC)/include/uapi -I$(KERNEL_SRC)/include/generated
BPF_CFLAGS += -D__TARGET_ARCH_$(ARCH) -O2 -Wall

.PHONY: all clean

all: monitor.bpf.o gatekeeper.bpf.o

# Generate vmlinux.h if not present (btfhub or bpftool)
vmlinux.h:
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h 2>/dev/null || true
	@test -f vmlinux.h || echo "Install kernel BTF or copy vmlinux.h from libbpf-bootstrap"

monitor.bpf.o: monitor.bpf.c vmlinux.h
	$(CLANG) $(BPF_CFLAGS) -target bpf -c $< -o $@

gatekeeper.bpf.o: gatekeeper.bpf.c vmlinux.h
	$(CLANG) $(BPF_CFLAGS) -target bpf -c $< -o $@

# User-space monitor (needs libbpf)
monitor: monitor.c monitor.bpf.o
	$(CC) -o monitor monitor.c -lbpf -lelf -lz -I/usr/include/bpf
	@echo "Run: sudo ./monitor (from dir containing monitor.bpf.o)"

clean:
	rm -f *.o monitor vmlinux.h
