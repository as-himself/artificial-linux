/* Artificial Linux - BPF LSM gatekeeper: allow SLM to block task allocation */
/* SPDX-License-Identifier: GPL-2.0 */

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

#define zero 0

struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __type(key, __u32);
    __type(value, __u32);
    __uint(max_entries, 1);
} control_map SEC(".maps");

SEC("lsm/task_alloc")
int BPF_PROG(restrict_task, struct task_struct *task, unsigned long clone_flags) {
    __u32 key = 0;
    __u32 *locked = bpf_map_lookup_elem(&control_map, &key);
    if (locked && *locked == 1) {
        bpf_printk("LSM: SLM lockdown active, blocking PID %d", bpf_get_current_pid_tgid() >> 32);
        return -EPERM;
    }
    return 0;
}

char LICENSE[] SEC("license") = "GPL";
