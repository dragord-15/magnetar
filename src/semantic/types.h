#ifndef MAGNETAR_SEMANTIC_TYPES_H
#define MAGNETAR_SEMANTIC_TYPES_H

typedef enum {
    TYPE_INT,
    TYPE_FLOAT,
    TYPE_BOOL,
    TYPE_STRING,
    TYPE_VOID,
    TYPE_STRUCT,
    TYPE_CLASS,
    TYPE_ENUM,
    TYPE_UNKNOWN
} DataTypeClass;

typedef struct DataType {
    DataTypeClass type_class;
    char* name;
    int size;
    struct DataType* base_type; // For arrays, ptrs, etc.
} DataType;

DataType* DataType_create(DataTypeClass tclass, const char* name, int size);
void DataType_free(DataType* type);

#endif // MAGNETAR_SEMANTIC_TYPES_H
