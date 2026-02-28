/*
 * Artificial Linux - User-space eBPF monitor: read ring buffer and send events to SLM
 * Compile: gcc -o monitor monitor.c -lbpf -lelf -lz -I/usr/include/bpf
 * Run: sudo ./monitor (or run as ebpf-monitor.service)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <bpf/libbpf.h>
#include <linux/types.h>

struct event_t {
    __u32 pid;
    char comm[16];
    char filename[128];
};

static int handle_event(void *ctx, void *data, size_t len) {
    const struct event_t *e = data;
    (void)ctx;
    (void)len;
    fprintf(stderr, "[ebpf-monitor] pid=%u comm=%s file=%s\n", e->pid, e->comm, e->filename);
    return 0;
}

int main(int argc, char **argv) {
    struct bpf_object *obj;
    struct bpf_map *map;
    struct ring_buffer *rb = NULL;
    int map_fd, err = 0;
    const char *obj_path = "monitor.bpf.o";

    (void)argc;
    (void)argv;

    obj = bpf_object__open(obj_path);
    if (libbpf_get_error(obj)) {
        fprintf(stderr, "Failed to open %s\n", obj_path);
        return 1;
    }

    err = bpf_object__load(obj);
    if (err) {
        fprintf(stderr, "Failed to load BPF object: %d\n", err);
        bpf_object__close(obj);
        return 1;
    }

    err = bpf_object__attach(obj);
    if (err) {
        fprintf(stderr, "Failed to attach: %d\n", err);
        bpf_object__close(obj);
        return 1;
    }

    map = bpf_object__find_map_by_name(obj, "rb");
    if (!map) {
        fprintf(stderr, "Map 'rb' not found\n");
        bpf_object__close(obj);
        return 1;
    }
    map_fd = bpf_map__fd(map);

    rb = ring_buffer__new(map_fd, handle_event, NULL, NULL);
    if (!rb) {
        fprintf(stderr, "Failed to create ring buffer\n");
        bpf_object__close(obj);
        return 1;
    }

    while (1) {
        err = ring_buffer__poll(rb, 1000);
        if (err == -EINTR) break;
    }

    ring_buffer__free(rb);
    bpf_object__close(obj);
    return 0;
}
