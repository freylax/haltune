// Mock HAL header for development/testing without LinuxCNC
#ifndef HAL_H
#define HAL_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// Basic type definitions
typedef int c_int;

// HAL constants
#define HAL_BIT 0
#define HAL_FLOAT 1
#define HAL_S32 2
#define HAL_U32 3
#define HAL_IN 16
#define HAL_OUT 32
#define HAL_IO 48
#define HAL_RO 64
#define HAL_RW 192
#define HAL_DIR_UNSPECIFIED 0

// HAL data types
typedef volatile bool hal_bit_t;
typedef volatile int32_t hal_s32_t;
typedef volatile uint32_t hal_u32_t;
typedef double hal_float_t;

// HAL data union - matches LinuxCNC HAL layout
typedef union {
    hal_bit_t b;
    hal_float_t f;
    hal_s32_t s;
    hal_u32_t u;
} hal_data_u;

// Stub functions (for compilation only)
static inline int hal_init(const char *name) { return -1; }
static inline void hal_exit(int comp_id) { (void)comp_id; }
static inline int hal_ready(int comp_id) { return -1; (void)comp_id; }
static inline void *hal_malloc(long size) { return NULL; (void)size; }
static inline int hal_pin_bit_new(const char *name, int dir, void **ptr, int comp_id) { return -1; (void)name; (void)dir; (void)ptr; (void)comp_id; }
static inline int hal_pin_float_new(const char *name, int dir, void **ptr, int comp_id) { return -1; (void)name; (void)dir; (void)ptr; (void)comp_id; }
static inline int hal_pin_s32_new(const char *name, int dir, void **ptr, int comp_id) { return -1; (void)name; (void)dir; (void)ptr; (void)comp_id; }
static inline int hal_pin_u32_new(const char *name, int dir, void **ptr, int comp_id) { return -1; (void)name; (void)dir; (void)ptr; (void)comp_id; }
static inline int hal_signal_new(const char *name, int type) { return -1; (void)name; (void)type; }
static inline int hal_link(const char *pin, const char *sig) { return -1; (void)pin; (void)sig; }
static inline int hal_unlink(const char *pin) { return -1; (void)pin; }
static inline int hal_signal_delete(const char *name) { return -1; (void)name; }

// HAL get/set functions - use hal_data_u ** like real LinuxCNC
static inline int hal_get_pin_value_by_name(const char *name, int *type, hal_data_u **data_ptr, bool *connected) {
    (void)name; (void)type; (void)data_ptr; (void)connected;
    return -1;
}
static inline int hal_get_param_value_by_name(const char *name, int *type, hal_data_u **data_ptr) {
    (void)name; (void)type; (void)data_ptr;
    return -1;
}
static inline int hal_get_signal_value_by_name(const char *name, int *type, hal_data_u **data_ptr, bool *has_writers) {
    (void)name; (void)type; (void)data_ptr; (void)has_writers;
    return -1;
}

// Stub halpr functions (internal HAL functions)
static inline void *halpr_find_pin_by_name(const char *name) { return NULL; (void)name; }
static inline void *halpr_find_param_by_name(const char *name) { return NULL; (void)name; }

#endif // HAL_H
