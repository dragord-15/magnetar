#include "../semantic/types.h"
#include <stdlib.h>
#include <string.h>

DataType* DataType_create(DataTypeClass tclass, const char* name, int size) {
    DataType* dt = (DataType*)malloc(sizeof(DataType));
    dt->type_class = tclass;
    dt->name = name ? strdup(name) : NULL;
    dt->size = size;
    dt->base_type = NULL;
    return dt;
}

void DataType_free(DataType* type) {
    if (!type) return;
    if (type->name) free(type->name);
    free(type);
}
