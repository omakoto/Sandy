CLANG ?= clang
BPFTOOL ?= bpftool
ARCH := $(shell uname -m | sed 's/x86_64/x86/' | sed 's/aarch64/arm64/' | sed 's/ppc64le/powerpc/' | sed 's/mips.*/mips/')

# Check if standard libbpf headers exist in /usr/include/bpf. If not, use kernel headers include path.
LIBBPF_CFLAGS :=
ifeq ($(wildcard /usr/include/bpf/bpf_helpers.h),)
    KERNEL_HEADERS := /usr/src/linux-headers-$(shell uname -r)/tools/bpf/resolve_btfids/libbpf/include
    ifneq ($(wildcard $(KERNEL_HEADERS)/bpf/bpf_helpers.h),)
        LIBBPF_CFLAGS := -I$(KERNEL_HEADERS)
    endif
endif

all: sandy_lsm.bpf.o

vmlinux.h:
	$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h

sandy_lsm.bpf.o: sandy_lsm.bpf.c vmlinux.h
	$(CLANG) -g -O2 -target bpf -D__TARGET_ARCH_$(ARCH) $(LIBBPF_CFLAGS) -c sandy_lsm.bpf.c -o sandy_lsm.bpf.o

clean:
	rm -f sandy_lsm.bpf.o vmlinux.h

.PHONY: all clean
