#ifndef MAGNETAR_JOB_SCHEDULER_H
#define MAGNETAR_JOB_SCHEDULER_H

#include <stddef.h>
#include <stdbool.h>
#include <pthread.h>

/*
 * Job Scheduler - نظام الترجمة المتوازية
 * يُحلّل تبعيات use/import ويُرتّب الملفات في مستويات
 * ويُترجم كل مستوى بالتوازي على عدة أنوية.
 * الإصدار v1.4.0 - المرحلة 3
 */

#define MAX_JOBS         512
#define MAX_WORKERS      16
#define MAX_DEPS         64

typedef enum {
    JOB_PENDING   = 0,
    JOB_RUNNING   = 1,
    JOB_DONE      = 2,
    JOB_FAILED    = 3
} JobStatus;

typedef struct {
    char*       filename;               /* مسار الملف المصدري */
    char*       output;                 /* مسار الملف الناتج  */
    char*       deps[MAX_DEPS];         /* قائمة التبعيات     */
    int         dep_count;
    int         level;                  /* مستوى الترجمة (0=أول) */
    JobStatus   status;
    int         exit_code;
    double      compile_time_ms;        /* زمن الترجمة بالمللي ثانية */
} CompileJob;

typedef struct {
    CompileJob*     jobs[MAX_JOBS];
    int             job_count;
    int             worker_count;
    pthread_t       workers[MAX_WORKERS];
    pthread_mutex_t queue_mutex;
    pthread_cond_t  queue_cond;
    int             next_job;           /* أول مهمة غير مُنجزة */
    bool            shutdown;
    int             completed;
    int             failed;
} JobScheduler;

/* ── واجهة برمجة JobScheduler ── */
JobScheduler* scheduler_create(int worker_count);
void          scheduler_free(JobScheduler* sched);
int           scheduler_add_job(JobScheduler* sched,
                                const char* filename,
                                const char* output);
void          scheduler_add_dep(JobScheduler* sched, int job_idx,
                                const char* dep_filename);
void          scheduler_compute_levels(JobScheduler* sched);
int           scheduler_run(JobScheduler* sched);   /* يُعيد 0 إذا نجح الكل */
void          scheduler_print_summary(JobScheduler* sched);

/* ── تحليل تبعيات use/import من ملف .fc ── */
int  scheduler_scan_deps(const char* filename,
                         char deps[][256], int max_deps);

/* ── دالة مساعدة: وقت بالمللي ثانية ── */
double scheduler_now_ms(void);

#endif /* MAGNETAR_JOB_SCHEDULER_H */
