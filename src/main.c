#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <ucontext.h>
#include "backend/backend.h"
#include "backend/elf_writer.h"
#include "backend/asm_writer.h"
#include "backend/bin_writer.h"
#include "lexer/lexer.h"
#include "parser/ast.h"
#include "parser/parser.h"
#include "semantic/symbols.h"
#include "ir/ir.h"
#include "runtime/gc.h"
#include "utils/diagnostics.h"

#define MAX_LOADED_MODULES 64
static char* loaded_modules[MAX_LOADED_MODULES];
static int loaded_module_count = 0;
static int preprocess_depth = 0;
static int preprocess_failed = 0;

/* Module/alias qualifiers such as `math.add(x)` or `m.add(x)` after
   `use "math.mg" as m;`. There is no real namespace object at runtime, so a
   qualifier is erased from the source before parsing. */
#define MAX_QUALIFIERS 64
static char* qualifier_names[MAX_QUALIFIERS];
static int qualifier_count = 0;

static void add_qualifier(const char* name, size_t len) {
    while (len > 0 && (name[len - 1] == ' ' || name[len - 1] == '\t'))
        len--;
    if (len == 0 || len >= 128) return;
    char buf[128];
    memcpy(buf, name, len);
    buf[len] = '\0';
    if (!(isalpha((unsigned char)buf[0]) || buf[0] == '_')) return;
    for (int i = 0; i < qualifier_count; i++) {
        if (strcmp(qualifier_names[i], buf) == 0) return;
    }
    if (qualifier_count < MAX_QUALIFIERS)
        qualifier_names[qualifier_count++] = strdup(buf);
}

static void clear_qualifiers(void) {
    for (int i = 0; i < qualifier_count; i++)
        free(qualifier_names[i]);
    qualifier_count = 0;
}

static bool is_ident_char(char c) {
    return isalnum((unsigned char)c) || c == '_';
}

/* Remove `alias.` / `alias::` prefixes outside strings and comments. */
static size_t rewrite_qualifiers(const char* in, size_t len, char* out,
                                 size_t out_size, int* in_block_comment) {
    size_t oi = 0;
    bool in_string = false;
    char quote = 0;
    bool escaped = false;

    for (size_t i = 0; i < len && oi + 1 < out_size; ) {
        char c = in[i];

        if (in_string) {
            out[oi++] = c;
            if (escaped) escaped = false;
            else if (c == '\\') escaped = true;
            else if (c == quote) in_string = false;
            i++;
            continue;
        }
        if (*in_block_comment) {
            out[oi++] = c;
            if (c == '*' && i + 1 < len && in[i + 1] == '/') {
                out[oi++] = '/';
                i += 2;
                *in_block_comment = 0;
            } else {
                i++;
            }
            continue;
        }
        if (c == '/' && i + 1 < len && in[i + 1] == '/') {
            while (i < len && oi + 1 < out_size) out[oi++] = in[i++];
            break;
        }
        if (c == '/' && i + 1 < len && in[i + 1] == '*') {
            out[oi++] = c; out[oi++] = in[i + 1];
            i += 2;
            *in_block_comment = 1;
            continue;
        }
        if (c == '"' || c == '\'') {
            in_string = true;
            quote = c;
            out[oi++] = c;
            i++;
            continue;
        }

        bool matched = false;
        if (i == 0 || !is_ident_char(in[i - 1])) {
            for (int q = 0; q < qualifier_count; q++) {
                size_t ql = strlen(qualifier_names[q]);
                if (i + ql >= len + 1) continue;
                if (strncmp(in + i, qualifier_names[q], ql) != 0) continue;
                size_t j = i + ql;
                if (j < len && in[j] == '.' &&
                    !(j + 1 < len && in[j + 1] == '.')) {
                    i = j + 1;
                    matched = true;
                    break;
                }
                if (j + 1 < len && in[j] == ':' && in[j + 1] == ':') {
                    i = j + 2;
                    matched = true;
                    break;
                }
            }
        }
        if (matched) continue;

        out[oi++] = c;
        i++;
    }
    out[oi] = '\0';
    return oi;
}

static int is_already_loaded(const char* name) {
    for (int i = 0; i < loaded_module_count; i++) {
        if (strcmp(loaded_modules[i], name) == 0) {
            return 1;
        }
    }
    return 0;
}

char* preprocess_source(const char* source, const char* source_dir);

static FILE* try_open_module_path(const char* candidate, char* found_path,
                                 size_t found_path_size) {
    FILE* f = fopen(candidate, "r");
    if (!f) return NULL;
    struct stat st;
    if (fstat(fileno(f), &st) != 0 || !S_ISREG(st.st_mode)) {
        fclose(f);
        return NULL;
    }
    snprintf(found_path, found_path_size, "%s", candidate);
    return f;
}

static FILE* try_open_module_base(const char* base, char* found_path,
                                  size_t found_path_size) {
    char candidate[2048];
    size_t n = strlen(base);
    int has_supported_ext = (n >= 3 && strcmp(base + n - 3, ".mg") == 0) ||
                            (n >= 3 && strcmp(base + n - 3, ".fc") == 0);
    if (strlen(base) >= sizeof(candidate)) return NULL;
    snprintf(candidate, sizeof(candidate), "%s", base);
    FILE* f = try_open_module_path(candidate, found_path, found_path_size);
    if (f || has_supported_ext) return f;

    const char* extensions[] = { ".mg", ".fc" };
    for (size_t i = 0; i < sizeof(extensions) / sizeof(extensions[0]); i++) {
        if (snprintf(candidate, sizeof(candidate), "%s%s", base, extensions[i]) >= (int)sizeof(candidate))
            continue;
        f = try_open_module_path(candidate, found_path, found_path_size);
        if (f) return f;
    }
    return NULL;
}

static FILE* try_open_joined(const char* directory, const char* name,
                             char* found_path, size_t found_path_size) {
    char candidate[2048];
    if (snprintf(candidate, sizeof(candidate), "%s/%s", directory, name) >= (int)sizeof(candidate))
        return NULL;
    return try_open_module_base(candidate, found_path, found_path_size);
}

static void get_source_dir(const char* filename, char* dir, size_t dir_size) {
    const char* slash = strrchr(filename, '/');
#ifdef _WIN32
    const char* backslash = strrchr(filename, '\\');
    if (!slash || (backslash && backslash > slash)) slash = backslash;
#endif
    if (!slash) {
        snprintf(dir, dir_size, ".");
        return;
    }
    size_t len = (size_t)(slash - filename);
    if (len == 0) len = 1;
    if (len >= dir_size) len = dir_size - 1;
    memcpy(dir, filename, len);
    dir[len] = '\0';
}

char* resolve_and_load_use(const char* name, const char* source_dir) {
    char path[2048];
    FILE* f = NULL;
    const char* local_name = name;
    const char* base_dir = source_dir ? source_dir : ".";
    /* A bare module name prefers the library directory beside its importer. */
    if (!strchr(local_name, '/') && local_name[0] != '/') {
        char candidate[2048];
        if (snprintf(candidate, sizeof(candidate), "%s/lib/%s", base_dir, local_name) < (int)sizeof(candidate))
            f = try_open_module_base(candidate, path, sizeof(path));
    }
    if (!f)
        f = try_open_joined(base_dir, local_name, path, sizeof(path));
    if (!f && local_name[0] != '/')
        f = try_open_module_base(local_name, path, sizeof(path));
    if (!f && !strchr(local_name, '/') && local_name[0] != '/')
        f = try_open_joined("lib", local_name, path, sizeof(path));

    /* Module paths and local lib/ candidates always precede configured/system libraries. */
    const char* env_path = getenv("MAGNETAR_LIB");
    if (!env_path) env_path = getenv("MAGNETAR_PATH");
    if (!env_path) env_path = getenv("MAGNETAR_HOME");
    if (!f && env_path && local_name[0] != '/')
        f = try_open_joined(env_path, local_name, path, sizeof(path));

    if (!f && local_name[0] != '/') {
        const char* home = getenv("HOME");
        const char* userprofile = getenv("USERPROFILE");
        const char* localappdata = getenv("LOCALAPPDATA");
        const char* system_paths[12];
        int path_count = 0;
        #if defined(__linux__) || defined(__unix__)
        system_paths[path_count++] = "/lib/magnetar/lib";
        system_paths[path_count++] = "/usr/local/lib/magnetar/lib";
        system_paths[path_count++] = "/usr/lib/magnetar/lib";
        system_paths[path_count++] = "/usr/share/magnetar/lib";
        system_paths[path_count++] = "/usr/local/share/magnetar/lib";
        system_paths[path_count++] = "/usr/local/lib/magnetar";
        system_paths[path_count++] = "/usr/lib/magnetar";
        #elif defined(__APPLE__)
        system_paths[path_count++] = "/opt/homebrew/lib/magnetar";
        system_paths[path_count++] = "/usr/local/lib/magnetar";
        system_paths[path_count++] = "/Library/Magnetar/lib";
        #elif defined(_WIN32) || defined(_WIN64)
        system_paths[path_count++] = "C:\\Program Files\\Magnetar\\lib";
        system_paths[path_count++] = "C:\\Magnetar\\lib";
        #else
        system_paths[path_count++] = "/usr/local/lib/magnetar";
        system_paths[path_count++] = "/usr/lib/magnetar";
        #endif
        for (int i = 0; i < path_count && !f; i++)
            f = try_open_joined(system_paths[i], local_name, path, sizeof(path));
        if (!f && home) {
            char home_lib[2048];
            if (snprintf(home_lib, sizeof(home_lib), "%s/.magnetar/lib", home) < (int)sizeof(home_lib))
                f = try_open_joined(home_lib, local_name, path, sizeof(path));
        }
        if (!f && localappdata) {
            char appdata_lib[2048];
            if (snprintf(appdata_lib, sizeof(appdata_lib), "%s/Magnetar/lib", localappdata) < (int)sizeof(appdata_lib))
                f = try_open_joined(appdata_lib, local_name, path, sizeof(path));
        }
        if (!f && userprofile) {
            char profile_lib[2048];
            if (snprintf(profile_lib, sizeof(profile_lib), "%s/.magnetar/lib", userprofile) < (int)sizeof(profile_lib))
                f = try_open_joined(profile_lib, local_name, path, sizeof(path));
        }
    }

    if (!f) {
        fprintf(stderr, "Error: Could not resolve use module '%s' from '%s'\n",
                local_name, base_dir);
        preprocess_failed = 1;
        return strdup("");
    }

    char canonical_path[4096];
    const char* module_key = realpath(path, canonical_path) ? canonical_path : path;
    if (is_already_loaded(module_key)) {
        fclose(f);
        return strdup("");
    }
    if (loaded_module_count >= MAX_LOADED_MODULES) {
        fclose(f);
        fprintf(stderr, "Error: Maximum loaded module count (%d) exceeded\n", MAX_LOADED_MODULES);
        preprocess_failed = 1;
        return strdup("");
    }
    loaded_modules[loaded_module_count++] = strdup(module_key);

    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    if (len < 0 || fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        fprintf(stderr, "Error: Could not read use module '%s'\n", path);
        preprocess_failed = 1;
        return strdup("");
    }
    char* content = (char*)malloc((size_t)len + 1);
    if (!content) {
        fclose(f);
        preprocess_failed = 1;
        fprintf(stderr, "Error: Out of memory while reading use module '%s'\n", path);
        return strdup("");
    }
    size_t read_bytes = fread(content, 1, len, f);
    if (read_bytes != (size_t)len) {
        fclose(f);
        free(content);
        preprocess_failed = 1;
        fprintf(stderr, "Error: Incomplete read of use module '%s'\n", path);
        return strdup("");
    }
    content[read_bytes] = '\0';
    fclose(f);

    char resolved_dir[1024];
    get_source_dir(path, resolved_dir, sizeof(resolved_dir));
    char* preprocessed = preprocess_source(content, resolved_dir);
    free(content);
    return preprocessed;
}

char* preprocess_source(const char* source, const char* source_dir) {
    if (preprocess_depth >= 32) {
        fprintf(stderr, "Error: Maximum module nesting depth (32) exceeded while resolving 'use' chains\n");
        preprocess_failed = 1;
        char* empty = (char*)malloc(1);
        empty[0] = '\0';
        return empty;
    }
    preprocess_depth++;
    size_t source_len = strlen(source);
    size_t buffer_size = source_len * 16 + 262144;
    char* buffer = (char*)malloc(buffer_size);
    buffer[0] = '\0';
    size_t b_len = 0;
    int in_block_comment = 0;

    const char* ptr = source;
    while (*ptr) {
        const char* p = ptr;
        while (*p == ' ' || *p == '\t') p++;

        if (strncmp(p, "use", 3) == 0 && (p[3] == ' ' || p[3] == '\t' || p[3] == '"' || p[3] == '\'')) {
            const char* start_mod = p + 3;
            while (*start_mod == ' ' || *start_mod == '\t') start_mod++;
            
            const char* end_semicolon = strchr(start_mod, ';');
            const char* end_newline = strchr(start_mod, '\n');
            
            if (end_semicolon && (!end_newline || end_semicolon < end_newline)) {
                char raw_mod[256];
                size_t mod_len = end_semicolon - start_mod;
                if (mod_len >= sizeof(raw_mod)) mod_len = sizeof(raw_mod) - 1;
                strncpy(raw_mod, start_mod, mod_len);
                raw_mod[mod_len] = '\0';

                /* `use X as Y;` imports X and registers Y as a qualifier, so
                   `Y.fn()` is parsed as `fn()` (there is no namespace object
                   at runtime). The alias must not become part of the module
                   path (`XasY`). */
                char* as_pos = NULL;
                for (char* q = raw_mod; *q; q++) {
                    if ((q == raw_mod || q[-1] == ' ' || q[-1] == '\t') &&
                        q[0] == 'a' && q[1] == 's' &&
                        (q[2] == ' ' || q[2] == '\t')) {
                        as_pos = q;
                        break;
                    }
                }
                if (as_pos) {
                    char* a = as_pos + 2;
                    while (*a == ' ' || *a == '\t') a++;
                    size_t alen = 0;
                    while (a[alen] && is_ident_char(a[alen])) alen++;
                    if (alen > 0) add_qualifier(a, alen);
                    *as_pos = '\0';
                }

                char clean_mod[256];
                size_t c_idx = 0;
                for (size_t i = 0; i < strlen(raw_mod); i++) {
                    char ch = raw_mod[i];
                    if (ch != '"' && ch != '\'' && ch != ' ' && ch != '\t' && ch != '\r') {
                        clean_mod[c_idx++] = ch;
                    }
                }
                clean_mod[c_idx] = '\0';

                char* final_mod = clean_mod;

                if (strlen(final_mod) > 0) {
                    char* imported_code = resolve_and_load_use(final_mod, source_dir);
                    if (imported_code) {
                        size_t imp_len = strlen(imported_code);
                        if (b_len + imp_len + 2 < buffer_size) {
                            memcpy(buffer + b_len, imported_code, imp_len);
                            b_len += imp_len;
                            buffer[b_len++] = '\n';
                            buffer[b_len] = '\0';
                        }
                        free(imported_code);
                    }
                }

                ptr = end_semicolon + 1;
                if (*ptr == '\r') ptr++;
                if (*ptr == '\n') ptr++;
                continue;
            }
        }

        const char* next_nl = strchr(ptr, '\n');
        size_t line_len = next_nl ? (size_t)(next_nl - ptr + 1) : strlen(ptr);
        if (qualifier_count > 0 && line_len > 0) {
            char* rewritten = (char*)malloc(line_len + 1);
            if (rewritten) {
                size_t rlen = rewrite_qualifiers(ptr, line_len, rewritten,
                                                 line_len + 1,
                                                 &in_block_comment);
                if (b_len + rlen < buffer_size) {
                    memcpy(buffer + b_len, rewritten, rlen);
                    b_len += rlen;
                    buffer[b_len] = '\0';
                }
                free(rewritten);
            }
        } else if (b_len + line_len < buffer_size) {
            memcpy(buffer + b_len, ptr, line_len);
            b_len += line_len;
            buffer[b_len] = '\0';
        }
        ptr += line_len;
    }

    preprocess_depth--;
    return buffer;
}

static int object_mode = 0;
#if defined(__aarch64__) || defined(__ARM_ARCH_8A__) || defined(_M_ARM64)
static const char* target_arch = "arm64"; /* build for the machine we run on */
#else
static const char* target_arch = "x86_64";
#endif
static const char* output_format = "elf"; /* elf, pe, asm, bin */
static const char* requested_format = NULL; /* explicit --format wins over target aliases */
static const char* entry_function = "main";
static int entry_explicit = 0;
static int bounds_check = 0;

/* Minimum crash diagnostics: if magc itself faults, report the faulting
   instruction pointer, stack/frame pointers and fault address before exiting.
   Generated programs are libc-free; their out-of-bounds protection is the
   separate compile-time `--bounds-check` path in the parser. */
static void magnetar_segv_handler(int signo, siginfo_t* info, void* context) {
    ucontext_t* uc = (ucontext_t*)context;
    unsigned long long rip = 0, rsp = 0, rbp = 0;
    const void* addr = info ? info->si_addr : NULL;
#if defined(__x86_64__) || defined(_M_X64)
    rip = (unsigned long long)uc->uc_mcontext.gregs[REG_RIP];
    rsp = (unsigned long long)uc->uc_mcontext.gregs[REG_RSP];
    rbp = (unsigned long long)uc->uc_mcontext.gregs[REG_RBP];
#elif defined(__aarch64__) || defined(__ARM_ARCH_8A__)
    rip = (unsigned long long)uc->uc_mcontext.pc;
    rsp = (unsigned long long)uc->uc_mcontext.sp;
    rbp = (unsigned long long)uc->uc_mcontext.regs[29];
#else
    (void)uc;
#endif
    fprintf(stderr, "SIGSEGV at rip=0x%llx rsp=0x%llx rbp=0x%llx addr=%p\n",
            rip, rsp, rbp, addr);
    _exit(128 + signo);
}

static void install_crash_handler(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = magnetar_segv_handler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSEGV, &sa, NULL);
}

int compile_file(const char* filename, const char* output_name) {
    FILE* file = fopen(filename, "r");
    if (!file) {
        fprintf(stderr, "Error: Cannot open '%s'\n", filename);
        return 1;
    }
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    fseek(file, 0, SEEK_SET);
    char* source = (char*)malloc(length + 1);
    if (fread(source, 1, length, file) != (size_t)length) {
        fclose(file);
        free(source);
        fprintf(stderr, "Error: Failed to read '%s'\n", filename);
        return 1;
    }
    source[length] = '\0';
    fclose(file);

    loaded_module_count = 0;
    preprocess_failed = 0;
    clear_qualifiers();
    char source_dir[1024];
    get_source_dir(filename, source_dir, sizeof(source_dir));
    char* preprocessed = preprocess_source(source, source_dir);
    if (preprocess_failed) {
        free(preprocessed);
        free(source);
        fprintf(stderr, "Error: Module preprocessing failed for '%s'\n", filename);
        return 1;
    }
    free(source);
    source = preprocessed;

    for (int i = 0; i < loaded_module_count; i++) {
        free(loaded_modules[i]);
    }
    loaded_module_count = 0;


    printf("[Magnetar] Compiling %s...\n", filename);

    GC_init();
    diag_init(filename, source);

    Lexer lexer;
    Lexer_init(&lexer, source);

    Parser parser;
    Parser_init(&parser, &lexer);
    Parser_set_bounds_check(bounds_check != 0);
    ASTNode* ast = Parser_parse(&parser);

    if (diag_has_errors() || parser.has_error) {
        diag_print_summary();
        free(source);
        ASTNode_free(ast);
        GC_shutdown();
        return 1;
    }

    /* status silenced */;
    IRProgram* ir = IRProgram_build(ast);
    IRProgram_optimize(ir);

    /* status silenced */;

    Backend* backend = backend_get(target_arch);
    if (!backend) {
        fprintf(stderr, "Error: Backend '%s' not found\n", target_arch);
        backend_list_all();
        IRProgram_free(ir);
        ASTNode_free(ast);
        free(source);
        GC_shutdown();
        return 1;
    }

    const char* selected_entry = entry_function;
    if (!entry_explicit && Parser_get_entry_name())
        selected_entry = Parser_get_entry_name();

    void* bstate = backend->create();
    if (backend->set_entry)
        backend->set_entry(bstate, selected_entry);
    if (backend->set_format)
        backend->set_format(bstate, output_format);
    BackendResult result;
    if (!backend->generate(bstate, ir, &result, object_mode)) {
        fprintf(stderr, "[Magnetar] Code generation failed\n");
        backend->destroy(bstate);
        IRProgram_free(ir);
        ASTNode_free(ast);
        free(source);
        GC_shutdown();
        return 1;
    }

    if (object_mode) {
        if (strcmp(output_format, "elf") != 0) {
            fprintf(stderr, "Error: --format %s cannot be combined with -c (object files are always ELF/MAGO).\n",
                    output_format);
            backend_result_free(&result);
            backend->destroy(bstate);
            IRProgram_free(ir);
            ASTNode_free(ast);
            free(source);
            GC_shutdown();
            return 1;
        }
        int res = backend->write_object(output_name, &result) ? 0 : 1;
        backend_result_free(&result);
        backend->destroy(bstate);
        IRProgram_free(ir);
        ASTNode_free(ast);
        free(source);
        GC_shutdown();
        return res;
    }

    /* Write executable (or the requested raw/text representation). */
    /* status silenced */;
    bool ok;
    if (strcmp(output_format, "asm") == 0)
        ok = asm_write_file(output_name, &result, target_arch);
    else if (strcmp(output_format, "bin") == 0)
        ok = bin_write_file(output_name, &result);
    else
        ok = backend->write_executable(output_name, &result);
    if (ok) {
        size_t total = result.code_size + result.rodata_size;
        printf("[Magnetar] Success! Created '%s' (%zu bytes)\n", output_name, total);
    } else {
        fprintf(stderr, "[Magnetar] Failed to write '%s'\n", output_name);
    }

    backend_result_free(&result);
    backend->destroy(bstate);
    IRProgram_free(ir);
    ASTNode_free(ast);
    free(source);
    GC_shutdown();

    return ok ? 0 : 1;
}

int main(int argc, char** argv) {
    install_crash_handler();
    if (argc < 2) {
        printf("Magnetar Compiler v3.5\n");
        printf("Usage: %s <source.mg> [-c] [-o <output>] [--target <arch>] [--format <fmt>] [--entry <name>] [--watch|-w]\n", argv[0]);
        printf("\nOptions:\n");
        printf("  -c                Compile to object file (.o)\n");
        printf("  -o <output>       Output file name\n");
        printf("  --target <arch>   Target: x86_64, arm64/aarch64 (native default on ARM), riscv, windows/win64\n");
        printf("  --format <fmt>    Output format: elf (default), pe (x86_64 only), asm, bin\n");
        printf("  --entry <name>    Entry function called at startup (default: main)\n");
        printf("  --bounds-check    Reject literal indices outside fixed-array bounds at compile time\n");
        printf("  -w, --watch       Live compile and run on file changes\n");
        printf("\nTargets status:\n");
        printf("  x86_64            Stable (ELF64 Linux, PE64 Windows)\n");
        printf("  arm64/aarch64     Working standalone ELF64 AArch64 (native on ARM)\n");
        printf("  riscv             Planned - not implemented\n");
        return 1;
    }

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            printf("Magnetar Compiler v3.5\n");
            printf("Usage: %s <source.mg> [-c] [-o <output>] [--target <arch>] [--format <fmt>] [--entry <name>] [--watch|-w]\n", argv[0]);
            printf("\nOptions:\n");
            printf("  -c                Compile to object file (.o)\n");
            printf("  -o <output>       Output file name\n");
            printf("  --target <arch>   Target: x86_64, arm64/aarch64 (native default on ARM), riscv, windows/win64\n");
            printf("  --format <fmt>    Output format: elf (default), pe (x86_64 only), asm, bin\n");
            printf("  --entry <name>    Entry function called at startup (default: main)\n");
            printf("  --bounds-check    Reject literal indices outside fixed-array bounds at compile time\n");
            printf("  -w, --watch       Live compile and run on file changes\n");
            printf("  -h, --help        Show this help message\n");
            printf("\nTargets status:\n");
            printf("  x86_64            Stable (ELF64 Linux, PE64 Windows)\n");
            printf("  arm64/aarch64     Working standalone ELF64 AArch64 (native on ARM)\n");
            printf("  riscv             Planned - not implemented\n");
            printf("\nFormats: elf (default), pe/windows/exe (x86_64 only), asm (text listing), bin (flat raw bytes).\n");
            return 0;
        }
    }

    backend_init_all();

    const char* filename = NULL;
    const char* output_name = NULL;
    int watch_mode = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-c") == 0) {
            object_mode = 1;
        } else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            output_name = argv[i + 1];
            i++;
        } else if (strcmp(argv[i], "--target") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --target requires an argument (x86_64, arm64, riscv)\n");
                return 1;
            }
        target_arch = argv[i + 1];
        if (strcmp(target_arch, "baremetal") == 0) {
            fprintf(stderr, "Error: --target=baremetal is not implemented yet.\n");
            fprintf(stderr, "       Baremetal target (no OS) is planned but not available in this version.\n");
            fprintf(stderr, "       Currently supported: x86_64, arm64/aarch64 (ELF); riscv is planned.\n");
            return 1;
        }
        if (strcmp(target_arch, "windows") == 0 || strcmp(target_arch, "x86_64-windows") == 0 || strcmp(target_arch, "win64") == 0) {
            target_arch = "x86_64";
            output_format = "pe";
        }
        if (strcmp(target_arch, "aarch64") == 0) target_arch = "arm64";
        i++;
        } else if (strncmp(argv[i], "--target=", 9) == 0) {
            target_arch = argv[i] + 9;
        if (strcmp(target_arch, "baremetal") == 0) {
            fprintf(stderr, "Error: --target=baremetal is not implemented yet.\n");
            fprintf(stderr, "       Baremetal target (no OS) is planned but not available in this version.\n");
            fprintf(stderr, "       Currently supported: x86_64, arm64/aarch64 (ELF); riscv is planned.\n");
            return 1;
        }
        if (strcmp(target_arch, "windows") == 0 || strcmp(target_arch, "x86_64-windows") == 0 || strcmp(target_arch, "win64") == 0) {
            target_arch = "x86_64";
            output_format = "pe";
        }
        if (strcmp(target_arch, "aarch64") == 0) target_arch = "arm64";
        } else if (strcmp(argv[i], "--format") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --format requires an argument (elf, pe, asm, bin)\n");
                return 1;
            }
            const char* fmt = argv[i + 1];
            if (strcmp(fmt, "elf") == 0) output_format = requested_format = "elf";
            else if (strcmp(fmt, "pe") == 0 || strcmp(fmt, "windows") == 0 || strcmp(fmt, "exe") == 0) output_format = requested_format = "pe";
            else if (strcmp(fmt, "asm") == 0 || strcmp(fmt, "s") == 0) output_format = requested_format = "asm";
            else if (strcmp(fmt, "bin") == 0 || strcmp(fmt, "binary") == 0) output_format = requested_format = "bin";
            else {
                fprintf(stderr, "Error: --format '%s' is not implemented yet.\n", fmt);
                fprintf(stderr, "       Supported: elf, pe (x86_64 only), asm, bin\n");
                return 1;
            }
            i++;
        } else         if (strncmp(argv[i], "--format=", 9) == 0) {
            const char* fmt = argv[i] + 9;
            if (strcmp(fmt, "elf") == 0) output_format = requested_format = "elf";
            else if (strcmp(fmt, "pe") == 0 || strcmp(fmt, "windows") == 0 || strcmp(fmt, "exe") == 0) output_format = requested_format = "pe";
            else if (strcmp(fmt, "asm") == 0 || strcmp(fmt, "s") == 0) output_format = requested_format = "asm";
            else if (strcmp(fmt, "bin") == 0 || strcmp(fmt, "binary") == 0) output_format = requested_format = "bin";
            else {
                fprintf(stderr, "Error: --format '%s' is not implemented yet.\n", fmt);
                fprintf(stderr, "       Supported: elf, pe (x86_64 only), asm, bin\n");
                return 1;
            }
        } else if (strcmp(argv[i], "--entry") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --entry requires a function name\n");
                return 1;
            }
            entry_function = argv[i + 1];
            entry_explicit = 1;
            i++;
        } else if (strncmp(argv[i], "--entry=", 8) == 0) {
            if (argv[i][8] == '\0') {
                fprintf(stderr, "Error: --entry requires a function name\n");
                return 1;
            }
            entry_function = argv[i] + 8;
            entry_explicit = 1;
        } else if (strcmp(argv[i], "--bounds-check") == 0) {
            bounds_check = 1;
        } else if (strcmp(argv[i], "--watch") == 0 || strcmp(argv[i], "-w") == 0) {
            watch_mode = 1;
        } else if (strncmp(argv[i], "--", 2) == 0) {
            fprintf(stderr, "Error: Unknown option '%s'\n", argv[i]);
            fprintf(stderr, "       Use --help for usage information.\n");
            return 1;
        } else if (argv[i][0] != '-') {
            filename = argv[i];
        }
    }

    /* An explicit --format is authoritative regardless of flag order. */
    if (requested_format) output_format = requested_format;

    /* PE64 is implemented only by the x86_64 backend.  Failing loudly here
       prevents --format pe from being silently ignored on ARM64/RISC-V. */
    if (strcmp(output_format, "pe") == 0 && strcmp(target_arch, "x86_64") != 0) {
        fprintf(stderr, "Error: PE64 output is only supported with --target x86_64 (got '%s').\n",
                target_arch);
        return 1;
    }

    if (!filename) {
        fprintf(stderr, "Error: No source file specified.\n");
        return 1;
    }

    if (!entry_function || !*entry_function) {
        fprintf(stderr, "Error: --entry requires a function name\n");
        return 1;
    }
    for (const char* e = entry_function; *e; e++) {
        if (!is_ident_char(*e)) {
            fprintf(stderr, "Error: invalid entry function name '%s'\n", entry_function);
            return 1;
        }
    }

    static char derived_output[512];
    if (!output_name) {
        if (object_mode) {
            strncpy(derived_output, filename, sizeof(derived_output) - 1);
            derived_output[sizeof(derived_output) - 1] = '\0';
            char* dot = strrchr(derived_output, '.');
            if (dot) {
                strcpy(dot, ".o");
            } else {
                strncat(derived_output, ".o", sizeof(derived_output) - strlen(derived_output) - 1);
            }
            output_name = derived_output;
        } else {
            output_name = (strcmp(output_format, "pe") == 0) ? "a.exe" : "a.out";
        }
    }

    if (!watch_mode) {
        return compile_file(filename, output_name);
    }

    // --- NATIVE LIVE CODING (WATCH MODE) ---
    struct stat file_stat;
    if (stat(filename, &file_stat) != 0) {
        fprintf(stderr, "Error: Cannot check file stats for '%s'\n", filename);
        return 1;
    }

    time_t last_mtime = file_stat.st_mtime;
    pid_t child_pid = 0;

    printf("\033[H\033[J");
    printf("\033[1;34m===================================================\033[0m\n");
    printf("\033[1;34m         MAGNETAR LIVE CODING                      \033[0m\n");
    printf("\033[1;34m===================================================\033[0m\n");
    printf("Watching: \033[1;33m%s\033[0m\n", filename);
    printf("Press \033[1;31mCtrl+C\033[0m to exit live coding mode...\n\n");

    if (compile_file(filename, output_name) == 0) {
        child_pid = fork();
        if (child_pid == 0) {
            char abs_output[512];
            snprintf(abs_output, sizeof(abs_output), "./%s", output_name);
            execl(abs_output, abs_output, NULL);
            perror("Execution failed");
            exit(1);
        }
    }

    while (1) {
        usleep(1000000);

        if (stat(filename, &file_stat) != 0) {
            if (compile_file(filename, output_name) == 0) {
            }
            continue;
        }

        if (file_stat.st_mtime != last_mtime) {
            last_mtime = file_stat.st_mtime;

            printf("\033[H\033[J");
            printf("\033[1;34m===================================================\033[0m\n");
            printf("\033[1;34m         MAGNETAR LIVE CODING                      \033[0m\n");
            printf("\033[1;34m===================================================\033[0m\n");
            printf("Watching: \033[1;33m%s\033[0m\n", filename);
            printf("Press \033[1;31mCtrl+C\033[0m to exit...\n\n");

            if (child_pid > 0) {
                kill(child_pid, SIGTERM);
                waitpid(child_pid, NULL, 0);
                child_pid = 0;
            }

            if (compile_file(filename, output_name) == 0) {
                child_pid = fork();
                if (child_pid == 0) {
                     char abs_output[512];
                     snprintf(abs_output, sizeof(abs_output), "./%s", output_name);
                     execl(abs_output, abs_output, NULL);
                     perror("Execution failed");
                     exit(1);
                }
                continue;
            }
            continue;
        }
    }

    return 0;
}
