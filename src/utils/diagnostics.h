#ifndef MAGNETAR_DIAGNOSTICS_H
#define MAGNETAR_DIAGNOSTICS_H

#include <stdbool.h>

// Initialize the diagnostics system for a new file
void diag_init(const char* filepath, const char* source_code);

// Report an error with a specific line, column, message, and an optional hint
void diag_report_error(int line, int col, const char* message, const char* token_text, const char* hint);

// Check if any errors occurred
bool diag_has_errors(void);

// Print a summary of all errors (if any)
void diag_print_summary(void);

#endif // MAGNETAR_DIAGNOSTICS_H
