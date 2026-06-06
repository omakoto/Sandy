CLANG ?= clang
BPFTOOL ?= bpftool
ARCH := $(shell uname -m | sed 's/x86_64/x86/' | sed 's/aarch64/arm64/' | sed 's/ppc64le/powerpc/' | sed 's/mips.*/mips/')

all: sandy_lsm.bpf.o

vmlinux.h:
	$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h

sandy_lsm.bpf.o: sandy_lsm.bpf.c vmlinux.h
	$(CLANG) -g -O2 -target bpf -D__TARGET_ARCH_$(ARCH) -c sandy_lsm.bpf.c -o sandy_lsm.bpf.o

clean:
	rm -f sandy_lsm.bpf.o vmlinux.h

.PHONY: all clean
