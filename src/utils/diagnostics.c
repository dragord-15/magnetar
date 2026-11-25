#include "diagnostics.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char* current_filepath = NULL;
static const char* current_source = NULL;
static int error_count = 0;
#define MAX_ERRORS 100

// ANSI escape codes for colors
#define COLOR_RESET   "\x1b[0m"
#define COLOR_RED     "\x1b[1;31m"
#define COLOR_GREEN   "\x1b[1;32m"
#define COLOR_YELLOW  "\x1b[1;33m"
#define COLOR_BLUE    "\x1b[1;34m"
#define COLOR_CYAN    "\x1b[1;36m"
#define COLOR_BOLD    "\x1b[1m"

void diag_init(const char* filepath, const char* source_code) {
    current_filepath = filepath;
    current_source = source_code;
    error_count = 0;
}

static void print_source_line(int target_line, int target_col) {
    if (!current_source) return;
    
    int line = 1;
    const char* p = current_source;
    const char* line_start = p;
    
    while (*p != '\0') {
        if (line == target_line) {
            line_start = p;
            while (*p != '\0' && *p != '\n') {
                p++;
            }
            int len = p - line_start;
            
            printf(COLOR_CYAN " %4d | " COLOR_RESET, line);
            
            for (int i = 0; i < len; i++) {
                putchar(line_start[i]);
            }
            printf("\n");
            
            printf("      | ");
            for (int i = 0; i < target_col - 1 && i < len; i++) {
                if (line_start[i] == '\t') putchar('\t');
                else putchar(' ');
            }
            printf(COLOR_RED "^" COLOR_RESET "\n");
            return;
        }
        
        if (*p == '\n') {
            line++;
        }
        p++;
    }
}

void diag_report_error(int line, int col, const char* message, const char* token_text, const char* hint) {
    if (error_count >= MAX_ERRORS) {
        if (error_count == MAX_ERRORS) {
            printf(COLOR_RED "Too many errors, stopping reporting.\n" COLOR_RESET);
            error_count++;
        }
        return;
    }
    
    printf("\n" COLOR_BOLD COLOR_RED "error" COLOR_RESET COLOR_BOLD ": %s\n" COLOR_RESET, message);
    printf(COLOR_BLUE "  --> " COLOR_RESET "%s:%d:%d\n", current_filepath ? current_filepath : "unknown", line, col);
    
    print_source_line(line, col);
    
    if (hint && strlen(hint) > 0) {
        printf(COLOR_GREEN "  = hint: " COLOR_RESET "%s\n", hint);
    } else if (token_text) {
        printf(COLOR_YELLOW "  = token: " COLOR_RESET "'%s'\n", token_text);
    }
    
    error_count++;
}

bool diag_has_errors(void) {
    return error_count > 0;
}

void diag_print_summary(void) {
    if (error_count > 0) {
        printf("\n" COLOR_BOLD COLOR_RED "✖ Compilation failed with %d error%s." COLOR_RESET "\n", 
               error_count > MAX_ERRORS ? MAX_ERRORS : error_count, 
               error_count == 1 ? "" : "s");
    } else {
        printf("\n" COLOR_BOLD COLOR_GREEN "✔ Compilation succeeded without syntax errors." COLOR_RESET "\n");
    }
}
