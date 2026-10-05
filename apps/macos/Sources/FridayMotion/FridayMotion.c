#include "FridayMotion.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>

// ABI facts for Apple's private HID event interface; no upstream detector code
// is vendored. See docs/chassis-activation.md for research and compatibility.
typedef void (*EventCallback)(void *, void *, void *, CFTypeRef);
typedef struct {
    CFTypeRef (*create)(CFAllocatorRef);
    void (*match)(CFTypeRef, CFDictionaryRef);
    CFArrayRef (*services)(CFTypeRef);
    bool (*setProperty)(CFTypeRef, CFStringRef, CFTypeRef);
    CFTypeRef (*copyProperty)(CFTypeRef, CFStringRef);
    void (*registerCallback)(CFTypeRef, EventCallback, void *, void *);
    void (*unregisterCallback)(CFTypeRef, EventCallback, void *, void *);
    void (*schedule)(CFTypeRef, dispatch_queue_t);
    void (*unschedule)(CFTypeRef, dispatch_queue_t);
    int (*eventType)(CFTypeRef);
    double (*value)(CFTypeRef, int);
    uint64_t (*timestamp)(CFTypeRef);
} API;

struct FridayMotionSession {
    API api;
    CFTypeRef client;
    CFTypeRef service;
    CFTypeRef originalInterval;
    mach_timebase_info_data_t timebase;
    FridayMotionSample callback;
    void *context;
};

static void sample(void *target, void *refcon, void *sender, CFTypeRef event) {
    FridayMotionSession *session = target;
    if (!session || !event || session->api.eventType(event) != 13) return;
    double time = (double)session->api.timestamp(event) * session->timebase.numer /
                  session->timebase.denom / 1e9;
    session->callback(session->context, time,
                      session->api.value(event, (13 << 16)),
                      session->api.value(event, (13 << 16) | 1),
                      session->api.value(event, (13 << 16) | 2));
}

FridayMotionSession *FridayMotionStart(FridayMotionSample callback, void *context,
                                      char *error, size_t errorSize) {
    FridayMotionSession *s = calloc(1, sizeof(*s));
    if (!s) { snprintf(error, errorSize, "Speicher für Bewegungssensor fehlt."); return NULL; }
#define LOAD(field, symbol) do { \
    s->api.field = dlsym(RTLD_DEFAULT, symbol); \
    if (!s->api.field) { snprintf(error, errorSize, "Bewegungssensor-API wird von macOS nicht unterstützt."); goto fail; } \
} while (0)
    LOAD(create, "IOHIDEventSystemClientCreate");
    LOAD(match, "IOHIDEventSystemClientSetMatching");
    LOAD(services, "IOHIDEventSystemClientCopyServices");
    LOAD(setProperty, "IOHIDServiceClientSetProperty");
    LOAD(copyProperty, "IOHIDServiceClientCopyProperty");
    LOAD(registerCallback, "IOHIDEventSystemClientRegisterEventCallback");
    LOAD(unregisterCallback, "IOHIDEventSystemClientUnregisterEventCallback");
    LOAD(schedule, "IOHIDEventSystemClientScheduleWithDispatchQueue");
    LOAD(unschedule, "IOHIDEventSystemClientUnscheduleFromDispatchQueue");
    LOAD(eventType, "IOHIDEventGetType");
    LOAD(value, "IOHIDEventGetFloatValue");
    LOAD(timestamp, "IOHIDEventGetTimeStamp");
#undef LOAD
    s->client = s->api.create(kCFAllocatorDefault);
    if (!s->client) { snprintf(error, errorSize, "Bewegungssensor konnte nicht geöffnet werden."); goto fail; }
    int page = 0xFF00, usage = 3;
    CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef u = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    const void *values[] = { p, u };
    CFDictionaryRef matching = CFDictionaryCreate(NULL, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    s->api.match(s->client, matching);
    CFRelease(matching); CFRelease(p); CFRelease(u);
    CFArrayRef services = s->api.services(s->client);
    if (!services || CFArrayGetCount(services) == 0) {
        if (services) CFRelease(services);
        snprintf(error, errorSize, "Kein lesbarer Gehäusesensor. Eingabeüberwachung für Friday prüfen."); goto fail;
    }
    s->service = CFRetain(CFArrayGetValueAtIndex(services, 0));
    CFRelease(services);
    s->originalInterval = s->api.copyProperty(s->service, CFSTR("ReportInterval"));
    int interval = 5000; // 200 Hz instead of continuous 800 Hz sampling.
    CFNumberRef rate = CFNumberCreate(NULL, kCFNumberIntType, &interval);
    bool accepted = s->api.setProperty(s->service, CFSTR("ReportInterval"), rate);
    CFRelease(rate);
    if (!accepted) { snprintf(error, errorSize, "Gehäusesensor verweigert den Zugriff. Eingabeüberwachung erlauben."); goto fail; }
    s->callback = callback; s->context = context;
    mach_timebase_info(&s->timebase);
    s->api.registerCallback(s->client, sample, s, NULL);
    s->api.schedule(s->client, dispatch_get_main_queue());
    return s;
fail:
    if (s->originalInterval) CFRelease(s->originalInterval);
    if (s->service) CFRelease(s->service);
    if (s->client) CFRelease(s->client);
    free(s);
    return NULL;
}

void FridayMotionStop(FridayMotionSession *s) {
    if (!s) return;
    s->api.unschedule(s->client, dispatch_get_main_queue());
    s->api.unregisterCallback(s->client, sample, s, NULL);
    // Restore the prior report rate instead of changing other sensor clients.
    int zero = 0;
    CFNumberRef idle = CFNumberCreate(NULL, kCFNumberIntType, &zero);
    s->api.setProperty(s->service, CFSTR("ReportInterval"), s->originalInterval ?: idle);
    CFRelease(idle);
    if (s->originalInterval) CFRelease(s->originalInterval);
    CFRelease(s->service); CFRelease(s->client); free(s);
}
