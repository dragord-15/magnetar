#include "job_scheduler.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

/* ── الوقت الحالي بالمللي ثانية ── */
double scheduler_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

/* ── إنشاء المُجدوِل ── */
JobScheduler* scheduler_create(int worker_count) {
    if (worker_count <= 0) worker_count = 1;
    if (worker_count > MAX_WORKERS) worker_count = MAX_WORKERS;

    JobScheduler* sched = (JobScheduler*)calloc(1, sizeof(JobScheduler));
    if (!sched) return NULL;

    sched->worker_count = worker_count;
    sched->next_job     = 0;
    sched->shutdown     = false;
    sched->completed    = 0;
    sched->failed       = 0;

    pthread_mutex_init(&sched->queue_mutex, NULL);
    pthread_cond_init(&sched->queue_cond, NULL);

    return sched;
}

/* ── إضافة مهمة ترجمة ── */
int scheduler_add_job(JobScheduler* sched,
                      const char* filename, const char* output) {
    if (!sched || sched->job_count >= MAX_JOBS) return -1;

    CompileJob* job = (CompileJob*)calloc(1, sizeof(CompileJob));
    job->filename  = strdup(filename);
    job->output    = output ? strdup(output) : NULL;
    job->dep_count = 0;
    job->level     = 0;
    job->status    = JOB_PENDING;
    job->exit_code = -1;

    int idx = sched->job_count++;
    sched->jobs[idx] = job;
    return idx;
}

/* ── إضافة تبعية لمهمة ── */
void scheduler_add_dep(JobScheduler* sched, int job_idx,
                       const char* dep_filename) {
    if (!sched || job_idx < 0 || job_idx >= sched->job_count) return;
    CompileJob* job = sched->jobs[job_idx];
    if (job->dep_count >= MAX_DEPS) return;
    job->deps[job->dep_count++] = strdup(dep_filename);
}

/* ── حساب مستويات الترجمة (Topological Sort) ── */
void scheduler_compute_levels(JobScheduler* sched) {
    if (!sched) return;
    bool changed = true;
    while (changed) {
        changed = false;
        for (int i = 0; i < sched->job_count; i++) {
            CompileJob* job = sched->jobs[i];
            for (int d = 0; d < job->dep_count; d++) {
                /* ابحث عن المهمة التي تنتج هذا الملف */
                for (int j = 0; j < sched->job_count; j++) {
                    if (j == i) continue;
                    CompileJob* dep_job = sched->jobs[j];
                    if (dep_job->output &&
                        strcmp(dep_job->output, job->deps[d]) == 0) {
                        int required_level = dep_job->level + 1;
                        if (job->level < required_level) {
                            job->level = required_level;
                            changed = true;
                        }
                    }
                }
            }
        }
    }
}

/* ── Worker thread: يُنفّذ مهام الترجمة ── */
typedef struct {
    JobScheduler* sched;
    int           level;      /* المستوى الذي يعمل عليه هذا الـ worker */
} WorkerArgs;

static void* worker_thread(void* arg) {
    WorkerArgs*   wa    = (WorkerArgs*)arg;
    JobScheduler* sched = wa->sched;
    int           level = wa->level;

    while (true) {
        pthread_mutex_lock(&sched->queue_mutex);

        /* البحث عن مهمة pending في المستوى الصحيح */
        int chosen = -1;
        for (int i = sched->next_job; i < sched->job_count; i++) {
            CompileJob* job = sched->jobs[i];
            if (job->level == level && job->status == JOB_PENDING) {
                job->status = JOB_RUNNING;
                chosen = i;
                break;
            }
        }

        if (chosen == -1 || sched->shutdown) {
            pthread_mutex_unlock(&sched->queue_mutex);
            break;
        }

        pthread_mutex_unlock(&sched->queue_mutex);

        /* تنفيذ الترجمة */
        CompileJob* job = sched->jobs[chosen];
        double t_start  = scheduler_now_ms();

        char cmd[1024];
        if (job->output)
            snprintf(cmd, sizeof(cmd), "./magc %s -o %s",
                     job->filename, job->output);
        else
            snprintf(cmd, sizeof(cmd), "./magc %s", job->filename);

        int ret = system(cmd);

        double t_end         = scheduler_now_ms();
        job->compile_time_ms = t_end - t_start;
        job->exit_code       = ret;

        pthread_mutex_lock(&sched->queue_mutex);
        job->status = (ret == 0) ? JOB_DONE : JOB_FAILED;
        if (ret == 0) sched->completed++;
        else          sched->failed++;
        pthread_cond_broadcast(&sched->queue_cond);
        pthread_mutex_unlock(&sched->queue_mutex);
    }

    free(wa);
    return NULL;
}

/* ── تشغيل كل المهام بالتوازي مستوىً بمستوى ── */
int scheduler_run(JobScheduler* sched) {
    if (!sched || sched->job_count == 0) return 0;

    scheduler_compute_levels(sched);

    /* تحديد الحد الأقصى للمستوى */
    int max_level = 0;
    for (int i = 0; i < sched->job_count; i++)
        if (sched->jobs[i]->level > max_level)
            max_level = sched->jobs[i]->level;

    /* تنفيذ مستوى بمستوى */
    for (int lvl = 0; lvl <= max_level; lvl++) {
        /* عدد المهام في هذا المستوى */
        int lvl_count = 0;
        for (int i = 0; i < sched->job_count; i++)
            if (sched->jobs[i]->level == lvl) lvl_count++;

        if (lvl_count == 0) continue;

        int threads = lvl_count < sched->worker_count
                      ? lvl_count : sched->worker_count;

        printf("[Scheduler] Level %d: %d jobs, %d threads\n",
               lvl, lvl_count, threads);

        pthread_t tids[MAX_WORKERS];
        for (int t = 0; t < threads; t++) {
            WorkerArgs* wa = (WorkerArgs*)malloc(sizeof(WorkerArgs));
            wa->sched = sched;
            wa->level = lvl;
            pthread_create(&tids[t], NULL, worker_thread, wa);
        }
        for (int t = 0; t < threads; t++)
            pthread_join(tids[t], NULL);
    }

    return sched->failed;
}

/* ── ملخص التنفيذ ── */
void scheduler_print_summary(JobScheduler* sched) {
    if (!sched) return;
    printf("\n[Scheduler] ═══ Compilation Summary ═══\n");
    printf("[Scheduler] Total:     %d jobs\n", sched->job_count);
    printf("[Scheduler] Completed: %d\n",      sched->completed);
    printf("[Scheduler] Failed:    %d\n",       sched->failed);
    double total_ms = 0;
    for (int i = 0; i < sched->job_count; i++) {
        CompileJob* job = sched->jobs[i];
        const char* st  = job->status == JOB_DONE   ? "✅" :
                          job->status == JOB_FAILED  ? "❌" :
                          job->status == JOB_RUNNING ? "⏳" : "⏸";
        printf("[Scheduler]   %s  L%d  %.1fms  %s\n",
               st, job->level, job->compile_time_ms, job->filename);
        total_ms += job->compile_time_ms;
    }
    printf("[Scheduler] Wall time: %.1f ms (vs %.1f ms sequential)\n",
           total_ms / sched->worker_count, total_ms);
}

/* ── تحرير المُجدوِل ── */
void scheduler_free(JobScheduler* sched) {
    if (!sched) return;
    for (int i = 0; i < sched->job_count; i++) {
        CompileJob* job = sched->jobs[i];
        free(job->filename);
        free(job->output);
        for (int d = 0; d < job->dep_count; d++) free(job->deps[d]);
        free(job);
    }
    pthread_mutex_destroy(&sched->queue_mutex);
    pthread_cond_destroy(&sched->queue_cond);
    free(sched);
}

/* ── تحليل تبعيات use من ملف المصدر ── */
int scheduler_scan_deps(const char* filename,
                        char deps[][256], int max_deps) {
    FILE* f = fopen(filename, "r");
    if (!f) return 0;
    char line[512];
    int  count = 0;
    while (fgets(line, sizeof(line), f) && count < max_deps) {
        /* مطابقة: "use name;" */
        char mod[256];
        if (sscanf(line, " use %248[a-zA-Z0-9_/] ;", mod) == 1) {
            snprintf(deps[count], 256, "lib/%.244s.fc", mod);
            count++;
        }
    }
    fclose(f);
    return count;
}

