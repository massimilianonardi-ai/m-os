#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#endif
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <sys/un.h>
#include <sys/time.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
extern char **environ;
static char *empty_environment[] = { NULL };

#if defined(__APPLE__)
#include <unistd.h>
#elif defined(__linux__)
#include <sys/socket.h>
#else
#error "srv supervisor currently supports Linux and macOS"
#endif

#define FIELD_MAX 65536U
#define ENVIRONMENT_MAX 4096U
#define ENVIRONMENT_BYTES_MAX (4U * 1024U * 1024U)
#define START_WAIT_SECONDS 1
#define STOP_WAIT_SECONDS 10
#define IDLE_EXIT_SECONDS 60
#define RESULT_STARTED 0
#define RESULT_ALREADY 1
#define RESULT_STOPPED 2
#define RESULT_NOT_RUNNING 3
#define RESULT_OTHER_OWNER 4
#define RESULT_ORPHANED 5
#define RESULT_START_FAILED 6
#define RESULT_STOP_TIMEOUT 7
#define RESULT_REQUEST_FAILED 8

struct service {
    char *run_root;
    char *runtime_dir;
    char *log_path;
    char *name;
    char *command;
    char *provider;
    pid_t pid;
    pid_t owner;
    struct service *next;
};

static struct service *services;
static volatile sig_atomic_t shutdown_requested;

static void on_signal(int sig) { (void)sig; shutdown_requested = 1; }

static uint32_t get_u32(const unsigned char *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static void put_u32(unsigned char *p, uint32_t v)
{
    p[0] = (unsigned char)(v >> 24); p[1] = (unsigned char)(v >> 16);
    p[2] = (unsigned char)(v >> 8); p[3] = (unsigned char)v;
}

static int read_all(int fd, void *buffer, size_t size)
{
    unsigned char *p = buffer;
    while (size != 0) {
        ssize_t n = read(fd, p, size);
        if (n == 0) return -1;
        if (n < 0) { if (errno == EINTR) continue; return -1; }
        p += (size_t)n; size -= (size_t)n;
    }
    return 0;
}

static int write_all(int fd, const void *buffer, size_t size)
{
    const unsigned char *p = buffer;
    while (size != 0) {
        ssize_t n = write(fd, p, size);
        if (n < 0) { if (errno == EINTR) continue; return -1; }
        if (n == 0) return -1;
        p += (size_t)n; size -= (size_t)n;
    }
    return 0;
}

static int read_field(int fd, char **out)
{
    unsigned char lenbuf[4];
    uint32_t len;
    char *value;
    if (read_all(fd, lenbuf, sizeof lenbuf) != 0) return -1;
    len = get_u32(lenbuf);
    if (len > FIELD_MAX) return -1;
    value = calloc((size_t)len + 1, 1);
    if (value == NULL) return -1;
    if (len != 0 && read_all(fd, value, len) != 0) { free(value); return -1; }
    value[len] = '\0';
    *out = value;
    return 0;
}

static int write_field(int fd, const char *value)
{
    size_t len = strlen(value);
    unsigned char lenbuf[4];
    if (len > FIELD_MAX) return -1;
    put_u32(lenbuf, (uint32_t)len);
    return write_all(fd, lenbuf, sizeof lenbuf) || write_all(fd, value, len) ? -1 : 0;
}

static int write_result(int fd, uint32_t result, pid_t pid)
{
    unsigned char data[8];
    put_u32(data, result);
    put_u32(data + 4, pid > 0 ? (uint32_t)pid : 0);
    return write_all(fd, data, sizeof data);
}

static int make_paths(const char *root, char *dir, size_t dircap, char *sock,
                      size_t sockcap, char *lock, size_t lockcap,
                      char *pidfile, size_t pidcap)
{
    int n;
    uint64_t root_hash = UINT64_C(14695981039346656037);
    const unsigned char *root_byte = (const unsigned char *)root;
    n = snprintf(dir, dircap, "%s/state/.s%lu", root, (unsigned long)getuid());
    if (n < 0 || (size_t)n >= dircap) return -1;
    while (*root_byte != 0) {
        root_hash ^= *root_byte++;
        root_hash *= UINT64_C(1099511628211);
    }
    /* A short, UID-private socket path also supports deeply nested checkouts. */
    n = snprintf(sock, sockcap, "/tmp/.m-srv-%lu-%016llx/s",
                 (unsigned long)getuid(), (unsigned long long)root_hash);
    if (n < 0 || (size_t)n >= sockcap) return -1;
    n = snprintf(lock, lockcap, "%s/.lock", dir);
    if (n < 0 || (size_t)n >= lockcap) return -1;
    n = snprintf(pidfile, pidcap, "%s/.pid", dir);
    return n < 0 || (size_t)n >= pidcap ? -1 : 0;
}

static int private_dir_prepare(const char *path)
{
    struct stat st;
    int created = 0;
    if (mkdir(path, 0700) == 0) created = 1;
    else if (errno != EEXIST) return -1;
    if (created && chmod(path, 0700) != 0) return -1;
    if (lstat(path, &st) != 0 || !S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode) ||
        st.st_uid != getuid() || (st.st_mode & 0777) != 0700) return -1;
    return 0;
}

static int root_state_validate(const char *root)
{
    char path[PATH_MAX];
    struct stat st;
    int n = snprintf(path, sizeof path, "%s/state", root);
    if (n < 0 || (size_t)n >= sizeof path) return -1;
    return lstat(path, &st) == 0 && S_ISDIR(st.st_mode) && !S_ISLNK(st.st_mode) ? 0 : -1;
}

/* 1 means possibly live, 0 means definitely absent, -1 is indeterminate. */
static int pid_maybe_alive(pid_t pid)
{
    if (kill(pid, 0) == 0 || errno == EPERM) return 1;
    if (errno == ESRCH) return 0;
    return -1;
}

static int peer_is_current_uid(int fd)
{
#if defined(__APPLE__)
    uid_t uid; gid_t gid;
    return getpeereid(fd, &uid, &gid) == 0 && uid == getuid();
#elif defined(__linux__)
    struct ucred cred;
    socklen_t len = sizeof cred;
    return getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) == 0 && cred.uid == getuid();
#endif
}

static int connect_socket(const char *path)
{
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    if (fd < 0) return -1;
    memset(&addr, 0, sizeof addr);
    addr.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof addr.sun_path) { close(fd); errno = ENAMETOOLONG; return -1; }
    strcpy(addr.sun_path, path);
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) { close(fd); return -1; }
    return fd;
}

static int socket_parent(const char *path, char *out, size_t cap)
{
    char *last_slash;
    int n = snprintf(out, cap, "%s", path);
    if (n < 0 || (size_t)n >= cap) return -1;
    last_slash = strrchr(out, '/');
    if (last_slash == NULL || last_slash == out) return -1;
    *last_slash = '\0';
    return 0;
}

static void set_socket_timeout(int fd, long seconds)
{
    struct timeval timeout;
    timeout.tv_sec = seconds;
    timeout.tv_usec = 0;
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
}

static int socket_path_prepare(const char *path)
{
    struct stat st;
    if (lstat(path, &st) != 0) return errno == ENOENT ? 0 : -1;
    if (!S_ISSOCK(st.st_mode) || st.st_uid != getuid()) return -1;
    return unlink(path);
}

static int serve_child_exec(const char *log_path, const char *bootstrap,
                            const char *command, char *const envp[])
{
    int logfd, nullfd;
    char *const args[] = { (char *)bootstrap, (char *)command, NULL };
    (void)signal(SIGPIPE, SIG_DFL);
    logfd = open(log_path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0600);
    if (logfd < 0) _exit(126);
    nullfd = open("/dev/null", O_RDONLY);
    if (nullfd < 0) _exit(126);
    if (dup2(nullfd, STDIN_FILENO) < 0 || dup2(logfd, STDOUT_FILENO) < 0 ||
        dup2(logfd, STDERR_FILENO) < 0) _exit(126);
    if (nullfd > STDERR_FILENO) close(nullfd);
    if (logfd > STDERR_FILENO) close(logfd);
    execve(bootstrap, args, envp);
    _exit(127);
}

static int write_record_file(const char *dir, const char *leaf, const char *value)
{
    char path[PATH_MAX];
    int fd, n, rc = -1;
    n = snprintf(path, sizeof path, "%s/%s", dir, leaf);
    if (n < 0 || (size_t)n >= sizeof path) return -1;
    fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) return -1;
    if (write_all(fd, value, strlen(value)) == 0 && write_all(fd, "\n", 1) == 0) rc = 0;
    if (close(fd) != 0) rc = -1;
    return rc;
}

static int runtime_dir_validate(const char *run_root, const char *name, char *out, size_t cap)
{
    struct stat st;
    int n;
    n = snprintf(out, cap, "%s/%s", run_root, name);
    if (n < 0 || (size_t)n >= cap) return -1;
    if (lstat(run_root, &st) != 0 || !S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode) || st.st_uid != getuid()) return -1;
    return 0;
}

static int read_record_pid(const char *runtime_dir, pid_t *pid)
{
    char path[PATH_MAX], data[64];
    char *end;
    struct stat st;
    int fd, n, k = 0;
    long value;
    n = snprintf(path, sizeof path, "%s/pid", runtime_dir);
    if (n < 0 || (size_t)n >= sizeof path) return -1;
    if (lstat(path, &st) != 0 || !S_ISREG(st.st_mode) || S_ISLNK(st.st_mode) || st.st_uid != getuid()) return -1;
    fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    while (k < (int)sizeof data - 1) {
        ssize_t r = read(fd, data + k, 1);
        if (r == 0 || data[k] == '\n') break;
        if (r < 0) { if (errno == EINTR) continue; close(fd); return -1; }
        k++;
    }
    close(fd);
    data[k] = '\0';
    if (k == 0) return -1;
    errno = 0; value = strtol(data, &end, 10);
    if (errno != 0 || end == data || *end != '\0' || value <= 0 || value > INT_MAX) return -1;
    *pid = (pid_t)value;
    return 0;
}

static int runtime_has_supervisor_marker(const char *dir)
{
    char path[PATH_MAX];
    struct stat st;
    int n = snprintf(path, sizeof path, "%s/supervisor", dir);
    if (n < 0 || (size_t)n >= sizeof path) return -1;
    if (lstat(path, &st) != 0) return errno == ENOENT ? 0 : -1;
    return S_ISREG(st.st_mode) && !S_ISLNK(st.st_mode) && st.st_uid == getuid() ? 1 : -1;
}

static int runtime_cleanup(const char *dir);

static uint32_t runtime_state_check(const char *dir, pid_t *pid)
{
    struct stat st;
    int record_status, marker_status;
    if (lstat(dir, &st) != 0) return errno == ENOENT ? RESULT_NOT_RUNNING : RESULT_REQUEST_FAILED;
    if (!S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode) || st.st_uid != getuid()) return RESULT_REQUEST_FAILED;
    record_status = read_record_pid(dir, pid);
    marker_status = runtime_has_supervisor_marker(dir);
    if (record_status == 0 && pid_maybe_alive(*pid) != 0) return RESULT_ORPHANED;
    if (record_status != 0 && marker_status != 0) return RESULT_ORPHANED;
    return runtime_cleanup(dir) == 0 ? RESULT_NOT_RUNNING : RESULT_REQUEST_FAILED;
}

static int runtime_cleanup(const char *dir)
{
    static const char *const leaves[] = { "pid", "owner", "command", "provider", "supervisor", "started" };
    char path[PATH_MAX];
    struct stat st;
    size_t i;
    if (lstat(dir, &st) != 0) return errno == ENOENT ? 0 : -1;
    if (!S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode) || st.st_uid != getuid()) return -1;
    for (i = 0; i < sizeof leaves / sizeof leaves[0]; i++) {
        int n = snprintf(path, sizeof path, "%s/%s", dir, leaves[i]);
        if (n < 0 || (size_t)n >= sizeof path) return -1;
        if (lstat(path, &st) == 0) {
            if (!S_ISREG(st.st_mode) || S_ISLNK(st.st_mode) || st.st_uid != getuid() || unlink(path) != 0) return -1;
        } else if (errno != ENOENT) return -1;
    }
    return rmdir(dir);
}

static int runtime_publish(const char *dir, pid_t pid, pid_t owner,
                           const char *command, const char *provider,
                           const char *socket_path)
{
    char tmp[PATH_MAX], pidbuf[32], ownerbuf[32];
    int n;
    n = snprintf(tmp, sizeof tmp, "%s.tmp.%ld", dir, (long)getpid());
    if (n < 0 || (size_t)n >= sizeof tmp) return -1;
    if (mkdir(tmp, 0700) != 0) return -1;
    if (chmod(tmp, 0700) != 0) { rmdir(tmp); return -1; }
    snprintf(pidbuf, sizeof pidbuf, "%ld", (long)pid);
    snprintf(ownerbuf, sizeof ownerbuf, "%ld", (long)owner);
    if (write_record_file(tmp, "pid", pidbuf) != 0 ||
        write_record_file(tmp, "owner", ownerbuf) != 0 ||
        write_record_file(tmp, "command", command) != 0 ||
        (provider[0] != '\0' && write_record_file(tmp, "provider", provider) != 0) ||
        write_record_file(tmp, "supervisor", socket_path) != 0 || rename(tmp, dir) != 0) {
        runtime_cleanup(tmp);
        return -1;
    }
    return 0;
}

static struct service *find_service(const char *run_root, const char *name)
{
    struct service *s;
    for (s = services; s != NULL; s = s->next)
        if (strcmp(s->run_root, run_root) == 0 && strcmp(s->name, name) == 0) return s;
    return NULL;
}

static void service_free(struct service *s, int remove_record)
{
    struct service **p = &services;
    while (*p != NULL && *p != s) p = &(*p)->next;
    if (*p == s) *p = s->next;
    if (remove_record) runtime_cleanup(s->runtime_dir);
    free(s->run_root); free(s->runtime_dir); free(s->log_path);
    free(s->name); free(s->command); free(s->provider); free(s);
}

static int service_reap(struct service *s)
{
    int status = 0;
    pid_t r;
    do { r = waitpid(s->pid, &status, WNOHANG); } while (r < 0 && errno == EINTR);
    if (r == 0) return 0;
    if (r == s->pid || (r < 0 && errno == ECHILD)) { (void)status; return 1; }
    return -1;
}

static int name_valid(const char *s)
{
    const unsigned char *p = (const unsigned char *)s;
    if (*p == 0 || *p == '.' || *p == '-') return 0;
    while (*p) {
        if (!((*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9') || *p == '.' || *p == '_' || *p == '-')) return 0;
        p++;
    }
    return s[strlen(s) - 1] != '.' && s[strlen(s) - 1] != '_' && s[strlen(s) - 1] != '-';
}

static uint32_t handle_request(const char *root, const char *socket_path, int fd)
{
    char *fields[10] = {0};
    char **request_env = NULL;
    char runtime_dir[PATH_MAX];
    size_t i;
    uint32_t env_count = 0;
    uint64_t env_bytes = 0;
    unsigned char countbuf[4];
    uint32_t result = RESULT_REQUEST_FAILED;
    pid_t pid = 0, owner;
    struct service *s;
    int force;
    char *owner_end;
    long owner_value;
    for (i = 0; i < 10; i++) if (read_field(fd, &fields[i]) != 0) goto done;
    if (read_all(fd, countbuf, sizeof countbuf) != 0) goto done;
    env_count = get_u32(countbuf);
    if (env_count > ENVIRONMENT_MAX) goto done;
    request_env = calloc((size_t)env_count + 1, sizeof *request_env);
    if (request_env == NULL) goto done;
    for (i = 0; i < env_count; i++) {
        char *equal;
        if (read_field(fd, &request_env[i]) != 0) goto done;
        env_bytes += strlen(request_env[i]) + 1;
        if (env_bytes > ENVIRONMENT_BYTES_MAX) goto done;
        equal = strchr(request_env[i], '=');
        if (equal == NULL || equal == request_env[i]) goto done;
    }
    if (strcmp(fields[0], root) != 0 || !name_valid(fields[3])) goto done;
    if (runtime_dir_validate(fields[1], fields[3], runtime_dir, sizeof runtime_dir) != 0) goto done;
    errno = 0; owner_value = strtol(fields[4], &owner_end, 10);
    if (errno != 0 || owner_end == fields[4] || *owner_end != '\0' || owner_value <= 0 || owner_value > INT_MAX) goto done;
    owner = (pid_t)owner_value;
    if (strcmp(fields[5], "0") != 0 && strcmp(fields[5], "1") != 0) goto done;
    force = strcmp(fields[5], "1") == 0;
    s = find_service(fields[1], fields[3]);
    if (s != NULL) {
        int child_state = service_reap(s);
        if (child_state == 1) { service_free(s, 1); s = NULL; }
        else if (child_state < 0) goto done;
    }

    if (strcmp(fields[6], "CHECK") == 0) {
        if (s != NULL) { pid = s->pid; result = RESULT_ALREADY; }
        else result = runtime_state_check(runtime_dir, &pid);
        goto done;
    } else if (strcmp(fields[6], "START") == 0) {
        if (s != NULL) { pid = s->pid; result = RESULT_ALREADY; goto done; }
        result = runtime_state_check(runtime_dir, &pid);
        if (result == RESULT_ORPHANED || result == RESULT_REQUEST_FAILED) goto done;
        {
            pid_t child = fork();
            struct service *next;
            if (child < 0) { result = RESULT_START_FAILED; goto done; }
            if (child == 0) serve_child_exec(fields[2], fields[7], fields[8], request_env);
            next = calloc(1, sizeof *next);
            if (next == NULL) { kill(child, SIGTERM); while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {} result = RESULT_START_FAILED; goto done; }
            next->run_root = strdup(fields[1]); next->runtime_dir = strdup(runtime_dir);
            next->log_path = strdup(fields[2]); next->name = strdup(fields[3]);
            next->command = strdup(fields[8]); next->provider = strdup(fields[9]);
            next->pid = child; next->owner = owner;
            if (!next->run_root || !next->runtime_dir || !next->log_path || !next->name || !next->command || !next->provider) {
                kill(child, SIGTERM); while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {}
                free(next->run_root); free(next->runtime_dir); free(next->log_path); free(next->name); free(next->command); free(next->provider); free(next);
                result = RESULT_START_FAILED; goto done;
            }
            next->next = services;
            services = next;
            if (runtime_publish(runtime_dir, child, owner, fields[8], fields[9], socket_path) != 0) {
                kill(child, SIGTERM); while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {}
                service_free(next, 0); result = RESULT_START_FAILED; goto done;
            }
            { struct timespec delay = { START_WAIT_SECONDS, 0 }; nanosleep(&delay, NULL); }
            { int child_state = service_reap(next); if (child_state == 1) { service_free(next, 1); result = RESULT_START_FAILED; goto done; } if (child_state < 0) { result = RESULT_REQUEST_FAILED; goto done; } }
            pid = child; result = RESULT_STARTED;
        }
    } else if (strcmp(fields[6], "STOP") == 0) {
        if (s == NULL) {
            result = runtime_state_check(runtime_dir, &pid);
            goto done;
        }
        pid = s->pid;
        if (!force && s->owner != owner) { result = RESULT_OTHER_OWNER; goto done; }
        { int child_state = service_reap(s); if (child_state == 1) { service_free(s, 1); result = RESULT_STOPPED; goto done; } if (child_state < 0) goto done; }
        if (kill(s->pid, SIGTERM) != 0 && errno != ESRCH) { result = RESULT_REQUEST_FAILED; goto done; }
        {
            int seconds;
            for (seconds = 0; seconds < STOP_WAIT_SECONDS; seconds++) {
                struct timespec delay = { 1, 0 };
                nanosleep(&delay, NULL);
                { int child_state = service_reap(s); if (child_state == 1) { service_free(s, 1); result = RESULT_STOPPED; goto done; } if (child_state < 0) goto done; }
            }
        }
        result = RESULT_STOP_TIMEOUT;
    } else goto done;

done:
    (void)write_result(fd, result, pid);
    for (i = 0; i < 10; i++) free(fields[i]);
    if (request_env != NULL) {
        for (i = 0; i < env_count; i++) free(request_env[i]);
        free(request_env);
    }
    return result;
}

static void reap_all(void)
{
    struct service *s = services, *next;
    while (s != NULL) { int child_state; next = s->next; child_state = service_reap(s); if (child_state == 1) service_free(s, 1); s = next; }
}

static void shutdown_children(void)
{
    struct service *s;
    for (s = services; s != NULL; s = s->next) {
        if (service_reap(s) == 0) kill(s->pid, SIGTERM);
    }
    for (;;) {
        reap_all();
        if (services == NULL) break;
        { struct timespec delay = { 0, 100000000 }; nanosleep(&delay, NULL); }
    }
}

static int server_main(const char *root, const char *socket_path, const char *lock_path,
                       const char *pidfile)
{
    int server, flags, lockfd;
    char socket_dir[PATH_MAX];
    struct flock lock;
    struct stat lockst;
    struct sockaddr_un addr;
    struct sigaction sa;
    time_t idle_since = 0;
    if (socket_parent(socket_path, socket_dir, sizeof socket_dir) != 0) return 1;
    umask(077);
    lockfd = open(lock_path, O_RDWR | O_CREAT | O_NOFOLLOW, 0600);
    if (lockfd < 0 || fstat(lockfd, &lockst) != 0 || !S_ISREG(lockst.st_mode) ||
        lockst.st_uid != getuid() || (lockst.st_mode & 0777) != 0600) {
        if (lockfd >= 0) close(lockfd);
        return 1;
    }
    memset(&lock, 0, sizeof lock); lock.l_type = F_WRLCK; lock.l_whence = SEEK_SET;
    if (fcntl(lockfd, F_SETLK, &lock) != 0) { close(lockfd); return 1; }
    flags = fcntl(lockfd, F_GETFD);
    if (flags >= 0) fcntl(lockfd, F_SETFD, flags | FD_CLOEXEC);
    if (socket_path_prepare(socket_path) != 0) { close(lockfd); return 1; }
    server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) { close(lockfd); return 1; }
    memset(&addr, 0, sizeof addr); addr.sun_family = AF_UNIX;
    if (strlen(socket_path) >= sizeof addr.sun_path) { close(server); close(lockfd); return 1; }
    strcpy(addr.sun_path, socket_path);
    if (bind(server, (struct sockaddr *)&addr, sizeof addr) != 0 || chmod(socket_path, 0600) != 0 || listen(server, 16) != 0) {
        close(server); close(lockfd); return 1;
    }
    {
        char pidbuf[32];
        int pfd;
        snprintf(pidbuf, sizeof pidbuf, "%ld\n", (long)getpid());
        pfd = open(pidfile, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (pfd < 0 || write_all(pfd, pidbuf, strlen(pidbuf)) != 0 || close(pfd) != 0) {
            if (pfd >= 0) close(pfd);
            close(server); close(lockfd); unlink(socket_path); return 1;
        }
    }
    memset(&sa, 0, sizeof sa); sa.sa_handler = on_signal; sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL); sigaction(SIGINT, &sa, NULL); sigaction(SIGHUP, &sa, NULL);
    flags = fcntl(server, F_GETFD); if (flags >= 0) fcntl(server, F_SETFD, flags | FD_CLOEXEC);
    for (;;) {
        fd_set reads; struct timeval timeout; int n;
        reap_all();
        if (shutdown_requested) break;
        if (services == NULL) {
            if (idle_since == 0) idle_since = time(NULL);
            if (time(NULL) - idle_since >= IDLE_EXIT_SECONDS) break;
        } else idle_since = 0;
        FD_ZERO(&reads); FD_SET(server, &reads); timeout.tv_sec = 1; timeout.tv_usec = 0;
        n = select(server + 1, &reads, NULL, NULL, &timeout);
        if (n < 0) { if (errno == EINTR) continue; break; }
        if (n == 0) continue;
        {
            int client = accept(server, NULL, NULL);
            if (client < 0) { if (errno == EINTR) continue; break; }
            set_socket_timeout(client, 30);
            flags = fcntl(client, F_GETFD);
            if (flags >= 0) fcntl(client, F_SETFD, flags | FD_CLOEXEC);
            if (peer_is_current_uid(client)) handle_request(root, socket_path, client);
            close(client);
        }
    }
    if (shutdown_requested) shutdown_children();
    close(server);
    unlink(socket_path);
    unlink(pidfile);
    rmdir(socket_dir);
    close(lockfd);
    return 0;
}

static int launch_server(const char *root, const char *dir, const char *socket_path,
                         const char *lock_path, const char *pidfile)
{
    int attempt;
    {
        pid_t child = fork();
        if (child < 0) return -1;
        if (child == 0) {
            pid_t grandchild;
            if (setsid() < 0) _exit(1);
            grandchild = fork();
            if (grandchild < 0) _exit(1);
            if (grandchild > 0) _exit(0);
            if (chdir("/") < 0) _exit(1);
            environ = empty_environment;
            { int fd = open("/dev/null", O_RDWR); if (fd >= 0) { dup2(fd, 0); dup2(fd, 1); dup2(fd, 2); if (fd > 2) close(fd); } }
            _exit(server_main(root, socket_path, lock_path, pidfile));
        }
        while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {}
    }
    for (attempt = 0; attempt < 100; attempt++) {
        int fd = connect_socket(socket_path);
        if (fd >= 0) { close(fd); return 0; }
        { struct timespec delay = { 0, 100000000 }; nanosleep(&delay, NULL); }
    }
    (void)dir;
    return -1;
}

static int send_request(const char *root, const char *run_root, const char *log_path,
                        const char *name, const char *owner, const char *force,
                        const char *action, const char *bootstrap,
                        const char *command, const char *provider)
{
    char dir[PATH_MAX], socket_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
    char socket_dir[sizeof(((struct sockaddr_un *)0)->sun_path)];
    char lock_path[PATH_MAX], pidfile[PATH_MAX];
    int fd, tries, rc = -1;
    unsigned char response[8];
    unsigned char countbuf[4];
    const char *fields[] = { root, run_root, log_path, name, owner, force, action, bootstrap, command, provider };
    if (root_state_validate(root) != 0 || make_paths(root, dir, sizeof dir, socket_path, sizeof socket_path,
                   lock_path, sizeof lock_path, pidfile, sizeof pidfile) != 0) return 1;
    if (socket_parent(socket_path, socket_dir, sizeof socket_dir) != 0) return 1;
    if (private_dir_prepare(dir) != 0 || private_dir_prepare(socket_dir) != 0) return 1;
    for (tries = 0; tries < 100; tries++) {
        fd = connect_socket(socket_path);
        if (fd < 0) {
            if (launch_server(root, dir, socket_path, lock_path, pidfile) != 0) {
                { struct timespec delay = { 0, 100000000 }; nanosleep(&delay, NULL); }
                fd = connect_socket(socket_path);
                if (fd < 0) continue;
            } else {
                fd = connect_socket(socket_path);
                if (fd < 0) continue;
            }
        }
        if (!peer_is_current_uid(fd)) { close(fd); return 1; }
        set_socket_timeout(fd, 30);
        for (size_t i = 0; i < sizeof fields / sizeof fields[0]; i++)
            if (write_field(fd, fields[i]) != 0) goto close_retry;
        {
            uint32_t env_count = 0;
            char **env;
            for (env = environ; env != NULL && *env != NULL; env++) {
                if (++env_count > ENVIRONMENT_MAX) goto close_retry;
            }
            put_u32(countbuf, env_count);
            if (write_all(fd, countbuf, sizeof countbuf) != 0) goto close_retry;
            for (env = environ; env != NULL && *env != NULL; env++)
                if (write_field(fd, *env) != 0) goto close_retry;
        }
        if (read_all(fd, response, sizeof response) != 0) goto close_retry;
        printf("%u %u\n", get_u32(response), get_u32(response + 4));
        rc = 0;
        close(fd);
        break;
close_retry:
        close(fd);
    }
    return rc == 0 ? 0 : 1;
}

int main(int argc, char **argv)
{
    (void)signal(SIGPIPE, SIG_IGN);
    if (argc == 3 && strcmp(argv[1], "--server-pid") == 0) {
        char dir[PATH_MAX], socket_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
        char lock_path[PATH_MAX], pidfile[PATH_MAX], data[64];
        int fd, n, len = 0;
        if (root_state_validate(argv[2]) != 0 || make_paths(argv[2], dir, sizeof dir, socket_path, sizeof socket_path,
                       lock_path, sizeof lock_path, pidfile, sizeof pidfile) != 0) return 1;
        fd = open(pidfile, O_RDONLY);
        if (fd < 0) return 1;
        while (len < (int)sizeof data - 1) {
            ssize_t got = read(fd, data + len, 1);
            if (got <= 0 || data[len] == '\n') break;
            len++;
        }
        close(fd); data[len] = '\0';
        n = (int)strtol(data, NULL, 10);
        if (n <= 0) return 1;
        printf("%d\n", n); return 0;
    }
    if (argc == 12 && strcmp(argv[1], "--request") == 0)
        return send_request(argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]);
    fputs("srv supervisor: invalid internal invocation\n", stderr);
    return 2;
}
