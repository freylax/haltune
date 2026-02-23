// HAL stub implementations for linking without LinuxCNC
//
// These stub functions allow haltune to link on systems without LinuxCNC installed.
// They always return NULL/error values to simulate HAL not being available.

#include <stddef.h>

// Stub halpr functions (internal HAL functions)
void *halpr_find_pin_by_name(const char *name) {
    (void)name;
    return NULL;
}

void *halpr_find_sig_by_name(const char *name) {
    (void)name;
    return NULL;
}

void *halpr_find_param_by_name(const char *name) {
    (void)name;
    return NULL;
}

void *halpr_find_pin_by_owner(int comp, void *start) {
    (void)comp;
    (void)start;
    return NULL;
}

void *halpr_find_param_by_owner(int comp, void *start) {
    (void)comp;
    (void)start;
    return NULL;
}

void *halpr_find_comp_by_name(const char *name) {
    (void)name;
    return NULL;
}

void *halpr_find_comp_by_id(int comp_id) {
    (void)comp_id;
    return NULL;
}
