#ifndef FRIDAY_MOTION_H
#define FRIDAY_MOTION_H

#include <stdbool.h>
#include <stddef.h>

typedef struct FridayMotionSession FridayMotionSession;
typedef void (*FridayMotionSample)(void *context, double time, double x, double y, double z);

// Main-thread lifecycle and callbacks. No key events or microphone input.
// Undocumented SPU symbols are loaded dynamically: unsupported OSes fail cleanly.
FridayMotionSession *FridayMotionStart(FridayMotionSample callback, void *context,
                                      char *error, size_t errorSize);
void FridayMotionStop(FridayMotionSession *session);
#endif
