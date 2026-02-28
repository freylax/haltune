#include <stdio.h>
#include <hal.h>

int main() {
    int count = 0;
    void *current = NULL;
    void *pin;
    
    while ((pin = halpr_find_pin_by_owner(NULL, current)) != NULL) {
        count++;
        current = pin;
        if (count <= 3) {
            hal_pin_t *p = (hal_pin_t *)pin;
            printf(Pin %d: %sn, count, p->name);
        }
    }
    
    printf(Total pins: %dn, count);
    return 0;
}
