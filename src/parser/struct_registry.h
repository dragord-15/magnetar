#ifndef MAGNETAR_STRUCT_REGISTRY_H
#define MAGNETAR_STRUCT_REGISTRY_H

#include <stdbool.h>
#include <string.h>

typedef struct {
    char* name;
    int offset;
    int field_type; // TokenType of the field (TOK_KW_FLOAT, TOK_KW_INT, etc.)
    /* 0 = scalar field. > 0 = the field is an array of that many elements
       (`int data[4];`); the backend then has to hand out the *address* of
       the field instead of its value. */
    int array_size;
    /* Multi-dimensional fields keep their shape (`int m[2][3];`). */
    int array_dim_count;
    int array_dims[8];
    int array_elem_type;
    bool is_volatile;
} StructField;

typedef struct {
    char* name;
    StructField fields[64];
    int field_count;
    int size;
} StructType;

extern StructType struct_types[128];
extern int struct_type_count;

static inline StructType* lookup_struct(const char* name) {
    for (int i = 0; i < struct_type_count; i++) {
        if (strcmp(struct_types[i].name, name) == 0) {
            return &struct_types[i];
        }
    }
    return NULL;
}

static inline int get_field_offset(StructType* st, const char* field_name) {
    if (!st) return -1;
    for (int i = 0; i < st->field_count; i++) {
        if (strcmp(st->fields[i].name, field_name) == 0) {
            return st->fields[i].offset;
        }
    }
    return -1;
}

/* Looks a field up and reports whether it is an array field.
   Returns NULL when the struct does not own such a field. */
static inline StructField* find_field(StructType* st, const char* field_name) {
    if (!st || !field_name) return NULL;
    for (int i = 0; i < st->field_count; i++) {
        if (st->fields[i].name && strcmp(st->fields[i].name, field_name) == 0) {
            return &st->fields[i];
        }
    }
    return NULL;
}

typedef struct {
    char* enum_name;
    char* member_name;
    int value;
} EnumMember;

extern EnumMember enum_members[256];
extern int enum_member_count;

static inline int lookup_enum_value(const char* enum_name, const char* member_name) {
    for (int i = 0; i < enum_member_count; i++) {
        if (strcmp(enum_members[i].enum_name, enum_name) == 0 &&
            strcmp(enum_members[i].member_name, member_name) == 0) {
            return enum_members[i].value;
        }
    }
    return -1;
}

static inline int is_enum_type(const char* name) {
    for (int i = 0; i < enum_member_count; i++) {
        if (strcmp(enum_members[i].enum_name, name) == 0) return 1;
    }
    return 0;
}

typedef struct {
    char* class_name;
    char* parent_name;
} ClassInheritance;

extern ClassInheritance class_inherits[64];
extern int class_inherits_count;

static inline const char* lookup_parent_class(const char* class_name) {
    for (int i = 0; i < class_inherits_count; i++) {
        if (strcmp(class_inherits[i].class_name, class_name) == 0) {
            return class_inherits[i].parent_name;
        }
    }
    return NULL;
}

#endif
