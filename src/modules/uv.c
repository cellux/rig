#define _GNU_SOURCE

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <pthread.h>

#include <uv.h>
#include <lua.h>

void *rig_dl_open(const char *path);
void *rig_dl_sym(void *handle, const char *name);
int rig_dl_close(void *handle);
const char *rig_dl_error(void);

typedef struct rig_uv_loop {
  uv_loop_t loop;
} rig_uv_loop_t;

typedef void (*rig_uv_spawn_exit_cb)(int64_t exit_status, int term_signal,
                                     const char *stdout_data,
                                     size_t stdout_len,
                                     const char *stderr_data,
                                     size_t stderr_len);
typedef void (*rig_uv_scandir_cb)(int status, const char *entries_data,
                                  size_t entries_len);
typedef void (*rig_uv_timer_cb)(void);

typedef struct rig_uv_process {
  uv_process_t process;
  uv_pipe_t stdout_pipe;
  uv_pipe_t stderr_pipe;
  rig_uv_spawn_exit_cb on_exit;
  char *stdout_data;
  size_t stdout_len;
  size_t stdout_capacity;
  char *stderr_data;
  size_t stderr_len;
  size_t stderr_capacity;
  int64_t exit_status;
  int term_signal;
  unsigned int pending_closes;
  bool exit_ready;
  bool process_closed;
  bool stdout_closed;
  bool stderr_closed;
  bool stdout_initialized;
  bool stderr_initialized;
} rig_uv_process_t;

typedef struct rig_uv_scandir {
  uv_fs_t req;
  rig_uv_scandir_cb on_done;
  char *entries_data;
  size_t entries_len;
  size_t entries_capacity;
} rig_uv_scandir_t;

typedef struct rig_uv_timer {
  uv_timer_t timer;
  rig_uv_timer_cb on_done;
} rig_uv_timer_t;

static void *rig_uv_library_handle = NULL;
static const char *rig_uv_loader_error = NULL;

static int (*rig_uv__loop_init)(uv_loop_t *loop) = NULL;
static int (*rig_uv__loop_close)(uv_loop_t *loop) = NULL;
static int (*rig_uv__run)(uv_loop_t *loop, uv_run_mode mode) = NULL;
static void (*rig_uv__stop)(uv_loop_t *loop) = NULL;
static const char *(*rig_uv__strerror)(int err) = NULL;
static int (*rig_uv__pipe_init)(uv_loop_t *loop, uv_pipe_t *handle, int ipc) = NULL;
static int (*rig_uv__spawn)(uv_loop_t *loop, uv_process_t *process,
                            const uv_process_options_t *options) = NULL;
static int (*rig_uv__read_start)(uv_stream_t *stream, uv_alloc_cb alloc_cb,
                                 uv_read_cb read_cb) = NULL;
static void (*rig_uv__close)(uv_handle_t *handle, uv_close_cb close_cb) = NULL;
static int (*rig_uv__process_kill)(uv_process_t *process, int signum) = NULL;
static int (*rig_uv__fs_scandir)(uv_loop_t *loop, uv_fs_t *req,
                                 const char *path, int flags,
                                 uv_fs_cb cb) = NULL;
static int (*rig_uv__fs_scandir_next)(uv_fs_t *req, uv_dirent_t *ent) = NULL;
static void (*rig_uv__fs_req_cleanup)(uv_fs_t *req) = NULL;
static int (*rig_uv__timer_init)(uv_loop_t *loop, uv_timer_t *handle) = NULL;
static int (*rig_uv__timer_start)(uv_timer_t *handle, uv_timer_cb cb,
                                  uint64_t timeout, uint64_t repeat) = NULL;
static int (*rig_uv__clock_gettime)(uv_clock_id clock_id,
                                    uv_timespec64_t *ts) = NULL;
static uint64_t (*rig_uv__hrtime)(void) = NULL;

static void rig_uv_set_loader_error(const char *message) {
  rig_uv_loader_error = message != NULL ? message : "unknown libuv loader error";
}

static int rig_uv_resolve_symbol(void **out, const char *name) {
  *out = rig_dl_sym(rig_uv_library_handle, name);
  if (*out == NULL) {
    rig_uv_set_loader_error(rig_dl_error());
    return -1;
  }
  return 0;
}

static int rig_uv_ensure_loaded(void) {
  if (rig_uv_library_handle != NULL) {
    return 0;
  }

  static const char *library_names[] = {
      "libuv.so.1",
      "libuv.so",
  };

  for (size_t i = 0; i < sizeof(library_names) / sizeof(library_names[0]); ++i) {
    rig_uv_library_handle = rig_dl_open(library_names[i]);
    if (rig_uv_library_handle != NULL) {
      break;
    }
  }

  if (rig_uv_library_handle == NULL) {
    rig_uv_set_loader_error(rig_dl_error());
    return -1;
  }

  if (rig_uv_resolve_symbol((void **)&rig_uv__loop_init, "uv_loop_init") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__loop_close, "uv_loop_close") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__run, "uv_run") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__stop, "uv_stop") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__strerror, "uv_strerror") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__pipe_init, "uv_pipe_init") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__spawn, "uv_spawn") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__read_start, "uv_read_start") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__close, "uv_close") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__process_kill, "uv_process_kill") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__fs_scandir, "uv_fs_scandir") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__fs_scandir_next, "uv_fs_scandir_next") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__fs_req_cleanup, "uv_fs_req_cleanup") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__timer_init, "uv_timer_init") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__timer_start, "uv_timer_start") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__clock_gettime, "uv_clock_gettime") != 0 ||
      rig_uv_resolve_symbol((void **)&rig_uv__hrtime, "uv_hrtime") != 0) {
    rig_dl_close(rig_uv_library_handle);
    rig_uv_library_handle = NULL;
    return -1;
  }

  return 0;
}

static void rig_uv_process_maybe_finish(rig_uv_process_t *process) {
  if (!process->exit_ready || process->pending_closes != 0) {
    return;
  }

  if (process->on_exit != NULL) {
    process->on_exit(process->exit_status, process->term_signal,
                     process->stdout_data, process->stdout_len,
                     process->stderr_data, process->stderr_len);
  }

  free(process->stdout_data);
  free(process->stderr_data);
  free(process);
}

static void rig_uv_on_handle_closed(uv_handle_t *handle) {
  rig_uv_process_t *process = handle->data;
  if (process == NULL) {
    return;
  }

  if (process->pending_closes > 0) {
    process->pending_closes -= 1;
  }
  rig_uv_process_maybe_finish(process);
}

static void rig_uv_close_process_handle(uv_handle_t *handle, bool *flag) {
  rig_uv_process_t *process = handle->data;
  if (*flag) {
    return;
  }

  *flag = true;
  process->pending_closes += 1;
  rig_uv__close(handle, rig_uv_on_handle_closed);
}

static void rig_uv_capture_append(char **data, size_t *len, size_t *capacity,
                                  const char *chunk, size_t chunk_len) {
  if (chunk_len == 0) {
    return;
  }

  if (*len + chunk_len > *capacity) {
    size_t new_capacity = *capacity == 0 ? 4096 : *capacity;
    while (*len + chunk_len > new_capacity) {
      new_capacity *= 2;
    }

    char *new_data = realloc(*data, new_capacity);
    if (new_data == NULL) {
      return;
    }

    *data = new_data;
    *capacity = new_capacity;
  }

  memcpy(*data + *len, chunk, chunk_len);
  *len += chunk_len;
}

static int rig_uv_scandir_append_entry(rig_uv_scandir_t *request,
                                       uv_dirent_type_t type,
                                       const char *name) {
  size_t name_len = strlen(name);
  size_t required = request->entries_len + 1 + name_len + 1;

  if (required > request->entries_capacity) {
    size_t new_capacity =
        request->entries_capacity == 0 ? 4096 : request->entries_capacity;
    while (required > new_capacity) {
      new_capacity *= 2;
    }

    char *new_data = realloc(request->entries_data, new_capacity);
    if (new_data == NULL) {
      return UV_ENOMEM;
    }

    request->entries_data = new_data;
    request->entries_capacity = new_capacity;
  }

  request->entries_data[request->entries_len] = (char)type;
  request->entries_len += 1;
  memcpy(request->entries_data + request->entries_len, name, name_len + 1);
  request->entries_len += name_len + 1;
  return 0;
}

static void rig_uv_finish_scandir(rig_uv_scandir_t *request, int status) {
  if (request->on_done != NULL) {
    request->on_done(status, request->entries_data, request->entries_len);
  }
  rig_uv__fs_req_cleanup(&request->req);
  free(request->entries_data);
  free(request);
}

static void rig_uv_on_scandir(uv_fs_t *req) {
  rig_uv_scandir_t *request = req->data;
  if (request == NULL) {
    return;
  }

  if (req->result < 0) {
    rig_uv_finish_scandir(request, (int)req->result);
    return;
  }

  uv_dirent_t entry;
  int rc = 0;
  while ((rc = rig_uv__fs_scandir_next(req, &entry)) != UV_EOF) {
    if (rc < 0) {
      rig_uv_finish_scandir(request, rc);
      return;
    }

    rc = rig_uv_scandir_append_entry(request, entry.type, entry.name);
    if (rc != 0) {
      rig_uv_finish_scandir(request, rc);
      return;
    }
  }

  rig_uv_finish_scandir(request, 0);
}

static void rig_uv_on_timer_closed(uv_handle_t *handle) {
  rig_uv_timer_t *timer = handle->data;
  if (timer != NULL) {
    free(timer);
  }
}

static void rig_uv_on_timer(uv_timer_t *handle) {
  rig_uv_timer_t *timer = handle->data;
  if (timer == NULL) {
    return;
  }

  if (timer->on_done != NULL) {
    timer->on_done();
  }

  rig_uv__close((uv_handle_t *)&timer->timer, rig_uv_on_timer_closed);
}

static void rig_uv_alloc_cb(uv_handle_t *handle, size_t suggested_size,
                            uv_buf_t *buf) {
  (void)handle;
  buf->base = malloc(suggested_size);
  buf->len = buf->base == NULL ? 0 : suggested_size;
}

static void rig_uv_read_cb(uv_stream_t *stream, ssize_t nread,
                           const uv_buf_t *buf) {
  rig_uv_process_t *process = stream->data;

  if (nread > 0) {
    if (stream == (uv_stream_t *)&process->stdout_pipe) {
      rig_uv_capture_append(&process->stdout_data, &process->stdout_len,
                            &process->stdout_capacity, buf->base,
                            (size_t)nread);
    } else {
      rig_uv_capture_append(&process->stderr_data, &process->stderr_len,
                            &process->stderr_capacity, buf->base,
                            (size_t)nread);
    }
  } else if (nread < 0) {
    if (stream == (uv_stream_t *)&process->stdout_pipe) {
      rig_uv_close_process_handle((uv_handle_t *)&process->stdout_pipe,
                                  &process->stdout_closed);
    } else {
      rig_uv_close_process_handle((uv_handle_t *)&process->stderr_pipe,
                                  &process->stderr_closed);
    }
  }

  free(buf->base);
}

static void rig_uv_on_process_exit(uv_process_t *handle, int64_t exit_status,
                                   int term_signal) {
  rig_uv_process_t *process = handle->data;
  process->exit_status = exit_status;
  process->term_signal = term_signal;
  process->exit_ready = true;

  rig_uv_close_process_handle((uv_handle_t *)&process->process,
                              &process->process_closed);
  rig_uv_close_process_handle((uv_handle_t *)&process->stdout_pipe,
                              &process->stdout_closed);
  rig_uv_close_process_handle((uv_handle_t *)&process->stderr_pipe,
                              &process->stderr_closed);
}

static void rig_uv_cleanup_failed_spawn(rig_uv_process_t *process) {
  process->exit_ready = true;
  process->on_exit = NULL;

  if (process->stdout_initialized) {
    rig_uv_close_process_handle((uv_handle_t *)&process->stdout_pipe,
                                &process->stdout_closed);
  }
  if (process->stderr_initialized) {
    rig_uv_close_process_handle((uv_handle_t *)&process->stderr_pipe,
                                &process->stderr_closed);
  }
  if (!process->stdout_initialized && !process->stderr_initialized) {
    rig_uv_process_maybe_finish(process);
  }
}

rig_uv_loop_t *rig_uv_loop_new(void) {
  if (rig_uv_ensure_loaded() != 0) {
    return NULL;
  }

  rig_uv_loop_t *loop = calloc(1, sizeof(rig_uv_loop_t));
  if (loop == NULL) {
    return NULL;
  }

  if (rig_uv__loop_init(&loop->loop) != 0) {
    free(loop);
    return NULL;
  }

  return loop;
}

int rig_uv_loop_delete(rig_uv_loop_t *loop) {
  if (loop == NULL) {
    return UV_EINVAL;
  }

  if (rig_uv_ensure_loaded() != 0) {
    return UV_ENOSYS;
  }

  int rc = rig_uv__loop_close(&loop->loop);
  if (rc == 0) {
    free(loop);
  }
  return rc;
}

int rig_uv_run(rig_uv_loop_t *loop) {
  if (loop == NULL) {
    return UV_EINVAL;
  }
  if (rig_uv_ensure_loaded() != 0) {
    return UV_ENOSYS;
  }
  return rig_uv__run(&loop->loop, UV_RUN_DEFAULT);
}

int rig_uv_run_nowait(rig_uv_loop_t *loop) {
  if (loop == NULL) {
    return UV_EINVAL;
  }
  if (rig_uv_ensure_loaded() != 0) {
    return UV_ENOSYS;
  }
  return rig_uv__run(&loop->loop, UV_RUN_NOWAIT);
}

void rig_uv_stop(rig_uv_loop_t *loop) {
  if (loop == NULL) {
    return;
  }
  if (rig_uv_ensure_loaded() != 0) {
    return;
  }
  rig_uv__stop(&loop->loop);
}

const char *rig_uv_strerror(int err) {
  if (rig_uv_library_handle == NULL || rig_uv__strerror == NULL) {
    return rig_uv_loader_error != NULL ? rig_uv_loader_error
                                       : "libuv shared library is not loaded";
  }
  return rig_uv__strerror(err);
}

int rig_uv_spawn_capture(rig_uv_loop_t *loop, const char *file,
                         const char *const *args, const char *cwd,
                         rig_uv_spawn_exit_cb on_exit) {
  if (loop == NULL || file == NULL || args == NULL || on_exit == NULL) {
    return UV_EINVAL;
  }
  if (rig_uv_ensure_loaded() != 0) {
    return UV_ENOSYS;
  }

  rig_uv_process_t *process = calloc(1, sizeof(rig_uv_process_t));
  if (process == NULL) {
    return UV_ENOMEM;
  }

  process->on_exit = on_exit;
  process->process.data = process;
  process->stdout_pipe.data = process;
  process->stderr_pipe.data = process;

  int rc = rig_uv__pipe_init(&loop->loop, &process->stdout_pipe, 0);
  if (rc != 0) {
    free(process);
    return rc;
  }
  process->stdout_initialized = true;

  rc = rig_uv__pipe_init(&loop->loop, &process->stderr_pipe, 0);
  if (rc != 0) {
    rig_uv_cleanup_failed_spawn(process);
    return rc;
  }
  process->stderr_initialized = true;

  uv_stdio_container_t stdio[3];
  memset(stdio, 0, sizeof(stdio));

  stdio[0].flags = UV_IGNORE;
  stdio[1].flags = UV_CREATE_PIPE | UV_WRITABLE_PIPE;
  stdio[1].data.stream = (uv_stream_t *)&process->stdout_pipe;
  stdio[2].flags = UV_CREATE_PIPE | UV_WRITABLE_PIPE;
  stdio[2].data.stream = (uv_stream_t *)&process->stderr_pipe;

  uv_process_options_t options;
  memset(&options, 0, sizeof(options));
  options.exit_cb = rig_uv_on_process_exit;
  options.file = file;
  options.args = (char **)args;
  options.cwd = cwd;
  options.stdio_count = 3;
  options.stdio = stdio;

  rc = rig_uv__spawn(&loop->loop, &process->process, &options);
  if (rc != 0) {
    rig_uv_cleanup_failed_spawn(process);
    return rc;
  }

  rc = rig_uv__read_start((uv_stream_t *)&process->stdout_pipe,
                         rig_uv_alloc_cb, rig_uv_read_cb);
  if (rc != 0) {
    rig_uv__process_kill(&process->process, SIGKILL);
    return 0;
  }

  rc = rig_uv__read_start((uv_stream_t *)&process->stderr_pipe,
                         rig_uv_alloc_cb, rig_uv_read_cb);
  if (rc != 0) {
    rig_uv__process_kill(&process->process, SIGKILL);
    return 0;
  }

  return 0;
}

int rig_uv_scandir(rig_uv_loop_t *loop, const char *path,
                   rig_uv_scandir_cb on_done) {
  if (loop == NULL || path == NULL || on_done == NULL) {
    return UV_EINVAL;
  }
  if (rig_uv_ensure_loaded() != 0) {
    return UV_ENOSYS;
  }

  rig_uv_scandir_t *request = calloc(1, sizeof(rig_uv_scandir_t));
  if (request == NULL) {
    return UV_ENOMEM;
  }

  request->on_done = on_done;
  request->req.data = request;

  int rc = rig_uv__fs_scandir(&loop->loop, &request->req, path, 0,
                              rig_uv_on_scandir);
  if (rc != 0) {
    rig_uv__fs_req_cleanup(&request->req);
    free(request);
    return rc;
  }

  return 0;
}

int rig_uv_sleep_once(rig_uv_loop_t *loop, uint64_t timeout_ms,
                      rig_uv_timer_cb on_done) {
  rig_uv_timer_t *timer;
  int rc;

  if (loop == NULL || on_done == NULL) {
    return UV_EINVAL;
  }
  if (rig_uv_ensure_loaded() != 0) {
    return UV_ENOSYS;
  }

  timer = calloc(1, sizeof(rig_uv_timer_t));
  if (timer == NULL) {
    return UV_ENOMEM;
  }

  timer->on_done = on_done;
  timer->timer.data = timer;

  rc = rig_uv__timer_init(&loop->loop, &timer->timer);
  if (rc != 0) {
    free(timer);
    return rc;
  }

  rc = rig_uv__timer_start(&timer->timer, rig_uv_on_timer, timeout_ms, 0);
  if (rc != 0) {
    rig_uv__close((uv_handle_t *)&timer->timer, rig_uv_on_timer_closed);
    return rc;
  }

  return 0;
}

int rig_uv_clock_read(int clock_id, int64_t *seconds, int32_t *nanoseconds) {
  uv_timespec64_t ts;
  int rc;

  if (seconds == NULL || nanoseconds == NULL) {
    return UV_EINVAL;
  }
  if (rig_uv_ensure_loaded() != 0) {
    return UV_ENOSYS;
  }

  rc = rig_uv__clock_gettime((uv_clock_id)clock_id, &ts);
  if (rc != 0) {
    return rc;
  }

  *seconds = ts.tv_sec;
  *nanoseconds = ts.tv_nsec;
  return 0;
}

int rig_uv_hrtime_read(uint64_t *value) {
  if (value == NULL) {
    return UV_EINVAL;
  }
  if (rig_uv_ensure_loaded() != 0) {
    return UV_ENOSYS;
  }

  *value = rig_uv__hrtime();
  return 0;
}

void rig_register_uv(lua_State *L) {
  lua_pushinteger(L, UV_CLOCK_MONOTONIC);
  lua_setfield(L, -2, "CLOCK_MONOTONIC");
  lua_pushinteger(L, UV_CLOCK_REALTIME);
  lua_setfield(L, -2, "CLOCK_REALTIME");
  lua_pushinteger(L, UV_DIRENT_UNKNOWN);
  lua_setfield(L, -2, "DIRENT_UNKNOWN");
  lua_pushinteger(L, UV_DIRENT_FILE);
  lua_setfield(L, -2, "DIRENT_FILE");
  lua_pushinteger(L, UV_DIRENT_DIR);
  lua_setfield(L, -2, "DIRENT_DIR");
  lua_pushinteger(L, UV_DIRENT_LINK);
  lua_setfield(L, -2, "DIRENT_LINK");
  lua_pushinteger(L, UV_DIRENT_FIFO);
  lua_setfield(L, -2, "DIRENT_FIFO");
  lua_pushinteger(L, UV_DIRENT_SOCKET);
  lua_setfield(L, -2, "DIRENT_SOCKET");
  lua_pushinteger(L, UV_DIRENT_CHAR);
  lua_setfield(L, -2, "DIRENT_CHAR");
  lua_pushinteger(L, UV_DIRENT_BLOCK);
  lua_setfield(L, -2, "DIRENT_BLOCK");
}
