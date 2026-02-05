#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
#include <zlib.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
#else
#include <dirent.h>
#endif

#define SEPARATOR '\x01'
#define CHUNK_SIZE 16384

static int filter_frames_name(const char *name) {
    size_t len = strlen(name);
    return len > 4 && strcmp(name + len - 4, ".txt") == 0;
}

#ifndef _WIN32
static int filter_frames(const struct dirent *entry) {
    return filter_frames_name(entry->d_name);
}

static int compare_frames(const struct dirent **a, const struct dirent **b) {
    return strcmp((*a)->d_name, (*b)->d_name);
}
#endif

static int compare_strings(const void *a, const void *b) {
    return strcmp(*(const char**)a, *(const char**)b);
}

static char *read_file(const char *path, size_t *out_size) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "Failed to open %s: %s\n", path, strerror(errno));
        return NULL;
    }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *buf = malloc(size);
    if (!buf) {
        return NULL;
    }

    if (fread(buf, 1, size, f) != (size_t)size) {
        fprintf(stderr, "Failed to read %s\n", path);
        return NULL;
    }

    fclose(f);
    *out_size = size;
    return buf;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <frames_dir> <output_file>\n", argv[0]);
        return 1;
    }

    const char *frames_dir = argv[1];
    const char *output_file = argv[2];

    char **filenames = NULL;
    int n = 0;
    int capacity = 0;

#ifdef _WIN32
    // Windows: use FindFirstFile/FindNextFile
    char search_path[4096];
    snprintf(search_path, sizeof(search_path), "%s\\*.txt", frames_dir);

    WIN32_FIND_DATAA ffd;
    HANDLE hFind = FindFirstFileA(search_path, &ffd);
    if (hFind == INVALID_HANDLE_VALUE) {
        fprintf(stderr, "Failed to scan directory %s: error %lu\n", frames_dir, GetLastError());
        return 1;
    }

    do {
        if (!(ffd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
            if (filter_frames_name(ffd.cFileName)) {
                if (n >= capacity) {
                    capacity = capacity == 0 ? 16 : capacity * 2;
                    filenames = realloc(filenames, capacity * sizeof(char*));
                }
                filenames[n] = _strdup(ffd.cFileName);
                n++;
            }
        }
    } while (FindNextFileA(hFind, &ffd) != 0);
    FindClose(hFind);

    // Sort filenames
    if (n > 0) {
        qsort(filenames, n, sizeof(char*), compare_strings);
    }
#else
    // POSIX: use scandir
    struct dirent **namelist;
    n = scandir(frames_dir, &namelist, filter_frames, compare_frames);
    if (n < 0) {
        fprintf(stderr, "Failed to scan directory %s: %s\n", frames_dir, strerror(errno));
        return 1;
    }

    // Convert to simple string array for uniform handling
    filenames = calloc(n, sizeof(char*));
    for (int i = 0; i < n; i++) {
        filenames[i] = strdup(namelist[i]->d_name);
        free(namelist[i]);
    }
    free(namelist);
#endif

    if (n == 0) {
        fprintf(stderr, "No frame files found in %s\n", frames_dir);
        return 1;
    }

    size_t total_size = 0;
    char **frame_contents = calloc(n, sizeof(char*));
    size_t *frame_sizes = calloc(n, sizeof(size_t));

    for (int i = 0; i < n; i++) {
        char path[4096];
#ifdef _WIN32
        snprintf(path, sizeof(path), "%s\\%s", frames_dir, filenames[i]);
#else
        snprintf(path, sizeof(path), "%s/%s", frames_dir, filenames[i]);
#endif
        
        frame_contents[i] = read_file(path, &frame_sizes[i]);
        if (!frame_contents[i]) {
            return 1;
        }
        
        total_size += frame_sizes[i];
        if (i < n - 1) total_size++;
    }

    char *joined = malloc(total_size);
    if (!joined) {
        fprintf(stderr, "Failed to allocate joined buffer\n");
        return 1;
    }

    size_t offset = 0;
    for (int i = 0; i < n; i++) {
        memcpy(joined + offset, frame_contents[i], frame_sizes[i]);
        offset += frame_sizes[i];
        if (i < n - 1) {
            joined[offset++] = SEPARATOR;
        }
    }

    uLongf compressed_size = compressBound(total_size);
    unsigned char *compressed = malloc(compressed_size);
    if (!compressed) {
        fprintf(stderr, "Failed to allocate compression buffer\n");
        return 1;
    }

    z_stream stream = {0};
    stream.next_in = (unsigned char*)joined;
    stream.avail_in = total_size;
    stream.next_out = compressed;
    stream.avail_out = compressed_size;

    // Use -MAX_WBITS for raw DEFLATE (no zlib wrapper)
    int ret = deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
    if (ret != Z_OK) {
        fprintf(stderr, "deflateInit2 failed: %d\n", ret);
        return 1;
    }

    ret = deflate(&stream, Z_FINISH);
    if (ret != Z_STREAM_END) {
        fprintf(stderr, "deflate failed: %d\n", ret);
        deflateEnd(&stream);
        return 1;
    }

    compressed_size = stream.total_out;
    deflateEnd(&stream);
    
    FILE *out = fopen(output_file, "wb");
    if (!out) {
        fprintf(stderr, "Failed to create %s: %s\n", output_file, strerror(errno));
        return 1;
    }

    if (fwrite(compressed, 1, compressed_size, out) != compressed_size) {
        fprintf(stderr, "Failed to write compressed data\n");
        return 1;
    }

    fclose(out);

    return 0;
}
